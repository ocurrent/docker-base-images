# Helper dockerfiles

They must be built using the root of the project as context:

``` shell
docker build -f docker/worker/Dockerfile .
```

## worker

ocluster worker to run in a Linux x86_64 pool to test local builds.
The worker uses Docker in Docker to run builds as the production cluster would on Linux.