---
name: airflow-dag-conventions
description: Airflow DAG structure conventions - module-level constants, default_args, and what must never run at import time.
---

# Airflow DAG conventions

Structural rules for a DAG file. The scheduler parses every file in `dags/` on a
loop, so a DAG file is not an ordinary script: code at module level runs on every
parse, not on every run.

## The import-time rule

**Nothing expensive at module level.** The scheduler re-parses each DAG file every
few seconds. Anything at module scope runs on every one of those parses.

```python
# Wrong - runs on every scheduler parse, not when the task runs
rows = PostgresHook(postgres_conn_id="dwh").get_records("SELECT ...")
config = requests.get("https://config.internal/dag").json()

with DAG(...) as dag:
    ...
```

A database query here runs hundreds of times an hour and blocks the parse loop. An
API call here fails the whole DAG file when the endpoint is down - the DAG vanishes
from the UI with an import error, and no task ever gets a chance to retry.

Put the work inside a callable that an operator invokes:

```python
def load_users() -> None:
    rows = PostgresHook(postgres_conn_id="dwh").get_records("SELECT ...")
```

The one deliberate exception is a DAG factory reading a config table - see
"Generated DAGs" below.

## File shape

Declare the identifiers a reader needs first, as module-level constants:

```python
OWNER = "team.data"
DAG_ID = "load_users_to_pg"
SHORT_DESCRIPTION = "Load users from the API into Postgres"
LONG_DESCRIPTION = """
# load_users_to_pg

What this DAG does, where the data comes from, who to call when it breaks.
"""

PG_CONN_ID = "dwh"
PG_SCHEMA = "public"
PG_TABLE = "users"
```

`DAG_ID` as a constant that is also the filename stem keeps grep, the UI, and the
file tree agreeing. Connection ids, schemas, and table names as constants keep the
targets visible at the top instead of buried in a SQL string.

## `default_args`

```python
args = {
    "owner": OWNER,
    "start_date": pendulum.datetime(2024, 1, 1, tz="Europe/Moscow"),
    "catchup": False,
    "retries": 1,
    "retry_delay": pendulum.duration(minutes=15),
    "depends_on_past": False,
}
```

- **`start_date` is fixed, never dynamic.** `pendulum.now()` or `days_ago(1)` makes
  the schedule move every time the file is parsed, so runs are skipped or
  duplicated unpredictably.
- **Use `pendulum` with an explicit `tz`.** A naive datetime picks up whatever the
  scheduler host is set to, and the DAG fires at a different wall-clock hour in
  another environment.
- **`catchup=False`** unless you have thought about backfill. Left at the default,
  a DAG with an old `start_date` floods the queue with historical runs the moment
  it is unpaused.
- **`retries` ≥ 1** for anything touching a network or a database. Transient
  failures are the common case in data work.

## The DAG block

```python
with DAG(
    dag_id=DAG_ID,
    schedule_interval="0 10 * * *",
    default_args=args,
    tags=["etl", "postgres"],
    catchup=False,
    description=SHORT_DESCRIPTION,
    max_active_tasks=1,
    max_active_runs=1,
) as dag:
    dag.doc_md = LONG_DESCRIPTION

    start = EmptyOperator(task_id="start")

    load = PythonOperator(
        task_id="load_users",
        python_callable=load_users,
    )

    end = EmptyOperator(task_id="end")

    start >> load >> end
```

- **`max_active_runs=1`** for any DAG that writes to a table. Without it a slow run
  overlaps the next one and two runs write the same target concurrently.
- **`tags`** are the only practical filter once the UI holds a few hundred DAGs.
  Tag by pipeline type and by target system.
- **`dag.doc_md`** renders in the UI. It is the one piece of documentation an
  on-call engineer will actually find at 3am.
- **`start` / `end` `EmptyOperator` bookends** give a stable attach point when the
  graph grows, so adding a parallel branch does not mean rewriting dependencies.

## Task granularity

One task per externally-visible step. A task is the unit Airflow retries, logs, and
displays - so a task that does three things reports one failure for three possible
causes, and retrying it re-runs the two steps that already succeeded.

Splitting the callable is a separate concern from splitting the task. See
[etl-decomposition](../ETL-DECOMPOSITION/SKILL.md): decomposition makes the code
testable, task boundaries make the failure legible.

## Generated DAGs

A factory that builds DAGs from a config table is a legitimate pattern - one
function returning a `DAG`, called once per config row:

```python
def create_kpi_dag(dag_id: str, cron_expression: str, sql_query: str, ...) -> DAG:
    ...
    return dag

for row in configs:
    globals()[row["dag_id"]] = create_kpi_dag(**row)
```

This is the exception to the import-time rule, and it comes with a cost: the config
read now happens on every scheduler parse. Two things follow.

- **Cache or bound the config read.** A full table scan on every parse is the usual
  way a factory takes down a scheduler.
- **When the config source is unreachable, every generated DAG disappears at once.**
  A single unreachable database removes the whole family from the UI. Decide
  deliberately whether that is acceptable, and prefer a source you control.

## Checklist

- [ ] No database, API, or file access at module level
- [ ] `start_date` fixed and timezone-aware
- [ ] `catchup` set explicitly
- [ ] `max_active_runs=1` if the DAG writes to a table
- [ ] `retries` set for network and database tasks
- [ ] `dag_id` matches the filename stem
- [ ] `tags` and `doc_md` present
- [ ] Each task is one externally-visible step
