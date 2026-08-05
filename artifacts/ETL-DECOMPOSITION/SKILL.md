---
name: etl-decomposition
description: Split monolithic extract-transform-load functions into testable units with the I/O at the edges.
---

# ETL decomposition

The most common shape in pipeline code is one function that fetches, reshapes, and
writes. It works, and it is untestable. This is how to split it and why the split
is worth the extra files.

## The anti-pattern

```python
def etl_load_user_to_pg():
    # 1. fetch
    response = requests.get("https://randomuser.me/api/")
    if response.status_code != 200:
        raise Exception(f"Fetch failed: {response.status_code}")
    user_data = response.json()

    # 2. reshape
    user = user_data["results"][0]
    first_name = user["name"]["first"]
    last_name = user["name"]["last"]
    email = user["email"]

    # 3. write
    pg_hook = PostgresHook(postgres_conn_id=PG_CONN_ID)
    insert_sql = f"""
        INSERT INTO {PG_SCHEMA}.{PG_TABLE} (first_name, last_name, email)
        VALUES (%(first_name)s, %(last_name)s, %(email)s);
    """
    pg_hook.run(sql=insert_sql, parameters={...})
```

The numbered comments are the tell. When a function needs `# 1.` `# 2.` `# 3.` to be
readable, those numbers are the seams it should have been split along.

**Why it resists testing.** The transform - the only part with real logic and real
edge cases - cannot be reached without an HTTP call and a live Postgres. Testing
that a missing `location` key is handled means standing up a database. So in
practice nobody tests it, and the reshape logic where the bugs actually live is the
least covered code in the pipeline.

Three more consequences:

- **One failure for three causes.** The task turns red for a 500, a schema change,
  or a dead database, and the log has to be read to tell which.
- **Retry re-runs everything.** A failed insert re-fetches from the API. If that API
  is rate-limited or paid, the retry costs real money.
- **Nothing is reusable.** The next DAG that needs the same API copies the block.

## The split

Three functions, each with one reason to fail:

```python
# extensions_api.py - I/O, no logic
def get_api_response(
    url: str,
    method: str = "GET",
    params: dict | None = None,
    headers: dict | None = None,
    timeout: int = 30,
) -> Any:
    response = requests.request(method=method, url=url, params=params,
                                headers=headers, timeout=timeout)
    response.raise_for_status()
    return response.json()


# extensions_transform.py - logic, no I/O
def extract_nested_fields(user_data: dict) -> dict[str, Any]:
    user = user_data["results"][0]
    return {
        "first_name": user["name"]["first"],
        "last_name": user["name"]["last"],
        "email": user["email"],
        "city": user["location"]["city"],
        "country": user["location"]["country"],
    }


# extensions_postgresql.py - I/O, no logic
def save_dict_to_postgres(
    conn_id: str, schema: str, table: str, dict_row: dict[str, Any]
) -> None:
    ...
```

The DAG callable becomes the composition, and nothing else:

```python
def etl_load_user_to_pg():
    api_data = get_api_response(url="https://randomuser.me/api/", timeout=600)
    user_row = extract_nested_fields(api_data)
    save_dict_to_postgres(
        conn_id=PG_CONN_ID, schema=PG_SCHEMA, table=PG_TABLE, dict_row=user_row
    )
```

## The rule that makes it work

**I/O at the edges, logic in the middle.** The transform takes a dict and returns a
dict. No network, no database, no clock, no environment. That single property is
what makes it testable without infrastructure:

```python
def test_extract_nested_fields():
    payload = {"results": [{"name": {"first": "A", "last": "B"},
                            "email": "a@b.c",
                            "location": {"city": "X", "country": "Y"}}]}
    assert extract_nested_fields(payload)["first_name"] == "A"
```

No mock, no fixture, no container. The I/O functions still need mocking - but they
are thin and rarely change, so that cost is paid once. See
[pytest-data-pipelines](../PYTEST-DATA-PIPELINES/SKILL.md) for how to mock them.

## Where to put the pieces

Extracted helpers go in an importable module next to the DAGs, not inside the DAG
file:

```text
dags/
  orchestration/
    load_users_to_pg.py          # DAG definition + composition
  extensions_for_orchestration/
    extensions_api.py            # HTTP
    extensions_transform.py      # reshaping
    extensions_postgresql.py     # database writes
```

Then point pytest at that directory so tests import the same way the DAG does:

```toml
[tool.pytest.ini_options]
pythonpath = ["dags"]
```

Without this, tests import helpers by a different path than Airflow does, and the
suite passes while the DAG fails on import.

## Keep the parameters honest

`get_api_response` takes `timeout` with a default of 30 and the caller passes 600 -
a deliberate override for a slow endpoint. Defaults belong in the helper; the
values that differ per pipeline belong at the call site. Hardcoding the timeout
inside the helper means the next caller forks it.

Do not add a parameter the current callers do not need. A helper with nine optional
arguments serving one call site is not more reusable, it is harder to read and
harder to test.

## When not to split

A callable that is genuinely one step - a single SQL statement, a file move - is
already decomposed. Splitting it into `get_sql()` and `run_sql()` adds indirection
and tests nothing. The trigger for splitting is **two or more reasons to fail in
one function**, not function length.
