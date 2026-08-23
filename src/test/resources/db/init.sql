-- Schema for the containerised API under test.
--
-- PostgREST exposes one Postgres schema as a REST API, so this file *is* the API
-- definition: the tables become endpoints, the foreign keys become embeddable
-- relationships, and the constraints become the 400s and 409s the negative scenarios
-- assert on. Error responses come from a real database rejecting real bad data rather
-- than from a mock told to return a number.
--
-- The domain is relational on purpose. A flat resource can be asserted on with any HTTP
-- client; nested JSON assembled from three joined tables is where Karate's `match` earns
-- its place, because the whole response can be compared against one shape in one line
-- instead of a dozen path lookups.

CREATE SCHEMA IF NOT EXISTS api;

-- ----------------------------------------------------------------- authors

CREATE TABLE api.authors (
    id         serial PRIMARY KEY,
    "name"     text NOT NULL CHECK (length(btrim("name")) > 0),
    country    text NOT NULL,
    -- UNIQUE gives the negative suite a real 409, and the CHECK a real 400.
    email      text NOT NULL UNIQUE CHECK (email LIKE '%@%.%')
);

-- ------------------------------------------------------------------- books

CREATE TABLE api.books (
    id         serial PRIMARY KEY,
    title      text NOT NULL CHECK (length(btrim(title)) > 0),
    -- The foreign key is what makes /books?select=*,author:authors(*) work at all.
    -- PostgREST derives embeddable relationships from the constraints, so dropping this
    -- does not merely lose referential integrity, it removes an endpoint shape.
    "authorId" integer NOT NULL REFERENCES api.authors (id) ON DELETE CASCADE,
    isbn       text NOT NULL UNIQUE CHECK (length(btrim(isbn)) = 13),
    "priceUsd" numeric(10, 2) NOT NULL CHECK ("priceUsd" >= 0),
    "pageCount" integer NOT NULL CHECK ("pageCount" > 0),
    published  date NOT NULL,
    "inPrint"  boolean NOT NULL DEFAULT true
);

-- ----------------------------------------------------------------- reviews

CREATE TABLE api.reviews (
    id         serial PRIMARY KEY,
    "bookId"   integer NOT NULL REFERENCES api.books (id) ON DELETE CASCADE,
    reviewer   text NOT NULL CHECK (length(btrim(reviewer)) > 0),
    rating     integer NOT NULL CHECK (rating BETWEEN 1 AND 5),
    body       text NOT NULL DEFAULT ''
);

-- -------------------------------------------------------------------- seed
--
-- Enough rows that the "there are at least N" preconditions hold on a cold container, so
-- no scenario has to create data merely to satisfy a Background. Every run starts from
-- exactly this state, which is the point of moving off a shared sandbox.

INSERT INTO api.authors (id, "name", country, email) VALUES
  (1, 'Ursula K. Le Guin', 'United States', 'ursula@example.com'),
  (2, 'Gabriel Garcia Marquez', 'Colombia',  'gabo@example.com'),
  (3, 'Italo Calvino',      'Italy',         'italo@example.com');
SELECT setval('api.authors_id_seq', 3, true);

INSERT INTO api.books (id, title, "authorId", isbn, "priceUsd", "pageCount", published, "inPrint") VALUES
  (1, 'The Left Hand of Darkness', 1, '9780441478125', 14.99, 304, '1969-03-01', true),
  (2, 'A Wizard of Earthsea',      1, '9780553383041', 11.50, 208, '1968-11-01', true),
  (3, 'One Hundred Years of Solitude', 2, '9780060883287', 16.00, 417, '1967-05-30', true),
  (4, 'Invisible Cities',          3, '9780156453806', 13.25, 165, '1972-01-01', false);
SELECT setval('api.books_id_seq', 4, true);

INSERT INTO api.reviews (id, "bookId", reviewer, rating, body) VALUES
  (1, 1, 'alex',  5, 'A thought experiment that never stops being one.'),
  (2, 1, 'sam',   4, 'Cold, in every sense.'),
  (3, 3, 'chris', 5, 'The family tree is the plot.'),
  (4, 4, 'robin', 4, 'Fifty-five cities, one city.');
SELECT setval('api.reviews_id_seq', 4, true);

-- --------------------------------------------------------- PostgREST roles
--
-- PostgREST connects as `authenticator` and switches to `web_anon` for unauthenticated
-- requests. Without the switch every request is rejected before it reaches a table, and
-- the failure looks like a broken container rather than a missing grant.

-- Anonymous callers may read and nothing else. Writing requires a JWT naming a role that has
-- been granted the privilege, which is the arrangement PostgREST is built around: the token
-- carries no permissions of its own, it names a Postgres role, and these grants decide what that
-- role can do. Authorisation lives in the schema, so it can be asserted on rather than mocked.
CREATE ROLE web_anon NOLOGIN;
GRANT USAGE ON SCHEMA api TO web_anon;
GRANT SELECT ON ALL TABLES IN SCHEMA api TO web_anon;

-- A reader that is authenticated and still may not write. Worth having as its own role: a suite
-- that only tests "anonymous cannot write" leaves the far more common production bug untouched,
-- which is a valid token whose role was granted more than anyone intended.
CREATE ROLE catalog_reader NOLOGIN;
GRANT USAGE ON SCHEMA api TO catalog_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA api TO catalog_reader;

CREATE ROLE catalog_writer NOLOGIN;
GRANT USAGE ON SCHEMA api TO catalog_writer;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA api TO catalog_writer;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA api TO catalog_writer;

CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD 'postgrest_pw';
GRANT web_anon TO authenticator;
GRANT catalog_reader TO authenticator;
GRANT catalog_writer TO authenticator;
