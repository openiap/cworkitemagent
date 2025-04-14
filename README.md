## C workitem agent example
This is a example project, functions as a template for how to get started writing a more controlable workitem agent for the OpenCore platform.

We connect to the server, and also register an event listener waiting for "SignedIn" events. 
When we get a "SignedIn" event, register a message queue based of the `queue` environment variable, and start listening for messages.
This should match the name of the workitem queue we want this agent to handle.

When we get a message, we will pop a workitem of the workitem queue, and if one is found ( in case more agents are listening )
we start processing it inside `ProcessWorkitem` 
We then update the state of the workitem to successful or retry, depending on the outcome of `ProcessWorkitem`.

When running inside an agent make sure the `wiq` environment variable has been set to the name of the workitem queue you want to listen to.
When running local, make sure to add this to your .env file.
If you need to use a different queue name from the workitem queue name, you can set the `queue` environment variable to something different.

```
https://github.com/openiap/cworkitemagent.git
```

# getting started
compile and run in debug mode

make will automaticly download clib_openiap.h and binary for current platform, if you cannot use make you need to, go to [rustapi](https://github.com/openiap/rustapi/releases) and download library for your platform and place them in the lib folder, and rename it to libopeniap_clib.so


```bash

setup default credentials
```bash
export apiurl=grpc://grpc.app.openiap.io:443
# username/password
export OPENIAP_USERNAME=username
export OPENIAP_PASSWORD=password
# or better, use a jwt token ( open https://app.openiap.io/jwtlong and copy the jwt value)
export OPENIAP_JWT=eyJhbGciOiJI....
```

```bash
make && ./workitem_client
# or with gcc directly
gcc main.c -Llib -lopeniap-linux-x64 -Wl,-rpath=lib -o workitem_client && ./workitem_client
```
