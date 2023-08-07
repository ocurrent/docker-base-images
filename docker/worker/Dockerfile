FROM ocurrent/ocluster-worker:alpine AS build

## Using a Docker in Docker container to run the worker
## See https://devopscube.com/run-docker-in-docker/
FROM docker:dind
RUN apk add rsync libev capnproto m4 sqlite libgmpxx curl gnupg git ca-certificates
RUN mkdir /var/cache/obuilder
WORKDIR /var/lib/ocluster-worker
ENTRYPOINT ["/usr/local/bin/ocluster-worker"]
ENV PROGRESS_NO_TRUNC=1
COPY --from=build /usr/local/bin/ocluster-worker /usr/local/bin/