## Coding Conventions

- Use **`printf()`** or OpenIAP-provided logging functions/macros like `info()`, `warn()`, and `error()`.
- Use `camel_case` for local variables and `snake_case` for functions.
- **Always free** response wrappers with their respective `free_*_response()` function.

---

## Initialization

Start with creating and connecting a client:

```c
#include "clib_openiap.h"

struct ClientWrapper *client = create_client();
struct ConnectResponseWrapper *resp = client_connect(client, "");
if (!resp || !resp->success) {
    error("Failed to connect: %s", resp ? resp->error : "null");
    return;
}
info("Connected successfully.");
free_connect_response(resp);
```

---

## Connection Lifecycle

You can reconnect at any time using:

```c
struct ConnectResponseWrapper *resp = client_connect(client, "");
// Always check for success and free the response
```

On reconnect, re-register any watches, queues, or gauges manually.

---

## API Reference

### Database Operations

```c
// Query
QueryRequestWrapper qreq = {
    .collectionname = "entities",
    .query = "{}",
    .projection = "{}",
    .orderby = NULL,
    .queryas = NULL,
    .explain = false,
    .skip = 0,
    .top = 10,
    .request_id = 1
};
QueryResponseWrapper *qres = query(client, &qreq);
free_query_response(qres);

// Distinct
DistinctRequestWrapper dreq = {
    .collectionname = "entities",
    .field = "_type",
    .request_id = 2
};
DistinctResponseWrapper *dres = distinct(client, &dreq);
free_distinct_response(dres);

// Insert One
InsertOneRequestWrapper ireq = {
    .collectionname = "entities",
    .item = "{\"name\":\"example\"}",
    .w = 1,
    .j = false,
    .request_id = 3
};
InsertOneResponseWrapper *ires = insert_one(client, &ireq);
free_insert_one_response(ires);
```

### Authentication

```c
SigninRequestWrapper sreq = {
    .username = "admin",
    .password = "admin",
    .longtoken = false,
    .request_id = 4
};
SigninResponseWrapper *sres = signin(client, &sreq);
free_signin_response(sres);
```

---

## Observability

```c
set_f64_observable_gauge("cpu_usage", 42.0, "CPU usage in percent");
set_u64_observable_gauge("users_online", 100, "Connected users");
set_i64_observable_gauge("errors", -1, "Error count");
disable_observable_gauge("cpu_usage");
```

---

## Events & Messaging

### Watch Events

```c
void watch_callback(struct WatchEventWrapper *event) {
    printf("Watch triggered: %s\n", event->document);
}

WatchRequestWrapper wreq = {
    .collectionname = "entities",
    .paths = NULL,
    .request_id = 5
};

watch_async_async(client, &wreq, watch_response_callback, watch_callback);
```

### Unwatch

```c
UnWatchResponseWrapper *uwres = unwatch(client, watch_id);
free_unwatch_response(uwres);
```

---

## Helpers

```c
client_disconnect(client);
free_client(client);

stringify(obj); // Only use if available for debug output
```

---

## Logging

Use the built-in logging functions:

- `info(const char *message)`
- `warn(const char *message)`
- `error(const char *message)`
- `debug(const char *message)`
- `trace(const char *message)`

Avoid `fprintf(stderr, ...)` unless absolutely needed.

---

## Example Pattern

```c
ClientWrapper *client = create_client();
ConnectResponseWrapper *resp = client_connect(client, "");
if (!resp || !resp->success) {
    error("Failed to connect.");
    return 1;
}
free_connect_response(resp);

// Perform query
QueryRequestWrapper req = {
    .collectionname = "entities",
    .query = "{}",
    .projection = "{}",
    .request_id = 1
};

QueryResponseWrapper *qres = query(client, &req);
if (qres && qres->success) {
    info("Query result: %s", qres->results);
}
free_query_response(qres);

client_disconnect(client);
free_client(client);
```
