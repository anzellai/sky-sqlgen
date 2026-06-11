-- USING (col) joins: the shared column appears ONCE in `*` expansion and a
-- bare reference to it is unambiguous (it is the coalesced join key).
CREATE TABLE employees (
    org_id INTEGER NOT NULL,
    emp_id INTEGER NOT NULL,
    name   TEXT    NOT NULL
);

CREATE TABLE orgs (
    org_id   INTEGER PRIMARY KEY,
    org_name TEXT    NOT NULL
);


-- INNER JOIN USING (org_id): `*` -> org_id (once), emp_id, name, org_name.
-- name: EmployeesWithOrg :many
SELECT *
FROM employees
JOIN orgs USING (org_id)
ORDER BY emp_id;


-- A bare `org_id` is the coalesced key (not ambiguous despite being in both).
-- name: EmployeeOrgNames :many
SELECT org_id, name, org_name
FROM employees
JOIN orgs USING (org_id)
ORDER BY emp_id;


-- LEFT JOIN USING (org_id): right-side `org_name` demotes to Maybe; the shared
-- `org_id` stays non-null (supplied by the always-present left side).
-- name: EmployeesLeftOrg :many
SELECT *
FROM employees
LEFT JOIN orgs USING (org_id)
ORDER BY emp_id;
