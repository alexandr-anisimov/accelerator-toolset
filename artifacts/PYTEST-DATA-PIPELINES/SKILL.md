---
name: pytest-data-pipelines
description: Testing data pipelines with pytest - unit/integration split, mocking at the I/O boundary, and DAG import tests.
---

# Testing data pipelines

Pipeline code resists testing for one reason: most of it touches a network or a
database. The split below is what makes the logic testable without infrastructure,
and keeps the infrastructure tests honest.

## Configure the layers first

```toml
[tool.pytest.ini_options]
testpaths = ["tests", "integration"]
pythonpath = ["dags"]
markers = [
    "unit: mark test as unit test",
    "integration: mark test as integration test",
    "db: mark test as using a database connection",
]
filterwarnings = ["error", "ignore::DeprecationWarning"]
```

- **`pythonpath = ["dags"]`** makes tests import helpers exactly as Airflow does.
  Without it the suite imports by a different path than the scheduler, and passes
  while the DAG fails on import.
- **Markers** let CI run `-m unit` on every push and `-m "integration or db"` on the
  branches where a database is actually available. Unmarked, the fast tests are
  hostage to container startup and nobody runs them locally.
- **`filterwarnings = ["error"]`** turns a deprecation into a failure while there is
  still time to act. Airflow and pandas both deprecate aggressively.

## Unit: the transform, with no mocks at all

If [etl-decomposition](../ETL-DECOMPOSITION/SKILL.md) has been applied, the transform
is a pure dict-to-dict function and needs no test infrastructure whatsoever:

```python
class TestExtractNestedFields:
    def test_extracts_flat_row(self):
        payload = {"results": [{"name": {"first": "Ada", "last": "Lovelace"},
                                "email": "ada@example.com",
                                "location": {"city": "London", "country": "UK"}}]}
        assert extract_nested_fields(payload) == {
            "first_name": "Ada", "last_name": "Lovelace",
            "email": "ada@example.com", "city": "London", "country": "UK",
        }

    def test_missing_nested_key_raises(self):
        with pytest.raises(KeyError):
            extract_nested_fields({"results": [{"name": {"first": "Ada"}}]})
```

**Test the empty and null cases explicitly.** They are where pipeline code actually
breaks, and they cost one line each:

```python
class TestDictKeysInStr:
    def test_empty_dict(self):
        assert dict_keys_in_str({}) == ""

    def test_none(self):
        assert dict_keys_in_str(None) == ""
```

A helper that returns `""` for `None` versus raising is a design decision. Pin it
with a test, because the calling code depends on it either way.

## Unit: mock at the boundary, and only there

Patch the function **where it is used**, not where it is defined:

```python
class TestGetApiResponse:
    @patch("extensions_for_orchestration.extensions_api.requests.request")
    def test_successful_get(self, mock_request):
        mock_response = MagicMock()
        mock_response.raise_for_status.return_value = None
        mock_response.json.return_value = {"status": "ok"}
        mock_request.return_value = mock_response

        result = get_api_response("https://example.com/api")

        mock_request.assert_called_once_with(
            method="GET", url="https://example.com/api",
            params=None, headers=None, timeout=30,
        )
        assert result == {"status": "ok"}
```

`@patch("...extensions_api.requests.request")` targets the module under test, not
`requests.request` globally. Patching the definition site misses callers that did
`from requests import request`.

**Assert on the call, not only the return value.** `assert_called_once_with` is what
catches a dropped `timeout` or a changed URL - a test that only checks the parsed
result passes even when the request went somewhere wrong.

Cover the failure paths, which is most of what an I/O wrapper is for:

```python
    @patch("extensions_for_orchestration.extensions_api.requests.request")
    def test_http_error_propagates(self, mock_request):
        mock_response = MagicMock()
        mock_response.raise_for_status.side_effect = HTTPError("404 Not Found")
        mock_request.return_value = mock_response

        with pytest.raises(HTTPError, match="404"):
            get_api_response("https://bad.url")
```

**Do not mock the database to test SQL.** A mocked cursor asserts that a string was
passed to a method - it cannot tell you the SQL is valid, the columns exist, or the
insert landed. That belongs in an integration test.

## Integration: a real database, real assertions

```python
@pytest.mark.integration
@pytest.mark.db
class TestSaveDictToPostgres:
    @staticmethod
    def create_test_users():
        execute_custom_query_postgres(port=5434, query="""
            DROP TABLE IF EXISTS users;
            CREATE TABLE users (
                user_id bigserial PRIMARY KEY,
                created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
                first_name text, last_name text, email text
            );
        """)

    def test_row_lands_in_table(self):
        self.create_test_users()
        save_dict_to_postgres(conn_id=self.create_pg_conn(), schema="public",
                              table="users",
                              dict_row={"first_name": "Ada", "email": "a@b.c"})
        rows = execute_custom_query_postgres(
            port=5434, query="SELECT first_name, email FROM users")
        assert rows == [("Ada", "a@b.c")]
```

**Create the table in the test.** A test depending on a table someone else left
behind passes or fails based on execution order.

**Assert on data read back, not on a return value.** The point of an integration
test is that the row is actually in the table.

Use a dedicated port and database for tests. Pointing integration tests at a shared
dev database means one developer's run truncates another's work.

## Airflow-specific tests

**The import test is the highest-value test in an Airflow repo** and costs three
lines:

```python
def test_no_import_errors():
    dagbag = DagBag(dag_folder="dags", include_examples=False)
    assert dagbag.import_errors == {}
```

A DAG file with a syntax error, a bad import, or a typo'd `pendulum.datetime(year=20240, ...)`
does not appear in the UI at all. Nothing runs, nothing alerts, and the pipeline is
simply absent. This test turns that silence into a red build.

Worth adding alongside it:

```python
def test_dags_have_owner_and_tags():
    dagbag = DagBag(dag_folder="dags", include_examples=False)
    for dag_id, dag in dagbag.dags.items():
        assert dag.default_args.get("owner"), f"{dag_id} has no owner"
        assert dag.tags, f"{dag_id} has no tags"

@pytest.mark.integration
def test_postgres_connection():
    hook = PostgresHook(postgres_conn_id="dwh")
    with hook.get_conn() as conn, conn.cursor() as cursor:
        cursor.execute("SELECT 1")
        assert cursor.fetchone() == (1,)
```

The connection test catches a missing Airflow connection, which otherwise fails at
3am inside a task rather than in CI.

## Coverage

100% line coverage on a pipeline is not 100% confidence. Coverage counts lines
executed, and pipeline bugs live in data shapes - a `NULL` where a value was assumed,
an empty result set, a duplicate key - not in unvisited lines.

A transform with one test on a happy-path payload can report full coverage while
every edge case is untested. Use coverage to find code nothing touches; use explicit
null/empty/duplicate cases to find bugs.

## Checklist

- [ ] `pythonpath` points at the DAGs directory
- [ ] `unit` / `integration` / `db` markers defined and applied
- [ ] Transform functions tested with no mocks
- [ ] Empty and `None` inputs tested explicitly
- [ ] I/O mocked where used, with `assert_called_once_with`
- [ ] SQL tested against a real database, never a mocked cursor
- [ ] `DagBag` import test present
- [ ] Integration tests create their own tables
