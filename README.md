This is an [OCurrent][] pipeline that builds Docker images for OCaml, for
various combinations of Linux distribution, OCaml version and architecture.

The resulting images can be run as e.g.

```
docker run --rm -it ocaml/opam:debian-10-ocaml-4.11
```

These images are very similar to the ones previously available as `ocaml/opam2`,
and use the same scripts from [avsm/ocaml-dockerfile][].
However, they are much smaller because each image only includes one OCaml compiler.

Each image includes two Dockerfiles showing how it was made:

- `/Dockerfile.opam` is the first stage, which just installs the `opam` binary.
- `/Dockerfile.ocaml` builds on the first stage by installing a particular opam switch.

The rest of this README is about working on the build pipeline.

## Testing locally

To see the pipeline, clone the repository and run `docker-compose up`:

```bash
git clone --recursive https://github.com/ocurrent/docker-base-images.git
docker-compose up
```

This runs with `--confirm harmless`, so that it will just show what it plans to do without trying to run any jobs yet.
You should see:

```
   current_web [INFO] Starting web server: (TCP (Port 8080))
```

If you now browse to <http://127.0.0.1:8080> you can see the build pipeline.
Note: It might complain about `--submission-service` being missing at first, but should fix itself once the scheduler service has started.
It should look something like this:

<p align='center' style='max-width: 50%'>
  <img src="./doc/pipeline.svg"/>
</p>

It starts by cloning opam-repository,
then creates images by installing an `opam` binary and a copy of opam-repository
for many Linux distributions and architectures.

These architecture-specific images get pushed to a staging repository on Docker Hub,
and are then combined into a single multi-arch image.

Separately, the architecture-specific base images are also used to create more images -
one for each supported OCaml compiler version.
These images are also pushed to a staging repository and then combined into multi-arch images.

You can click on a box (e.g. the opam-repository clone step) and then on `Start now` to run that step manually, or
you can set the confirmation threshold to `>= Average` on the main page.
The docker-compose file includes a single builder running locally, using the `linux-x86_64` pool and limited to one build at a time.
You might want to update this, or add more builders.
See the [OCluster][] documentation for more information about that.

The pipeline is defined in [pipeline.ml][].
This includes the Dockerfile definitions used to build the images.

Once running with your chosen configuration, you can use the web UI to raise (or remove) the confirmation threshold.

## The real deployment

The builder currently runs on `ci.ocamllabs.io`.
The configuration is in `stack.yml`.
To update it:

```
docker --context ci.ocamllabs.io stack deploy -c stack.yml base-images
```

If you are doing your own deployment, you will need to provide some secrets (using `docker secret create`):

- `ocurrent-hub` is the Docker Hub password, which is used to push the images.
- `ocurrent-ssh-key` is needed for any builders that are accessed over SSH.
- `ocurrent-tls-key` is needed for any builders that are accessed over TLS.
- `ocurrent-slack-endpoint` allows pushing status messages to a Slack channel.

[OCurrent]: https://github.com/ocurrent/ocurrent
[pipeline.ml]: https://github.com/ocurrent/docker-base-images/blob/master/src/pipeline.ml
[conf.ml]: https://github.com/ocurrent/docker-base-images/blob/master/src/conf.ml
[avsm/ocaml-dockerfile]: https://github.com/avsm/ocaml-dockerfile
[OCluster]: https://github.com/ocurrent/ocluster
