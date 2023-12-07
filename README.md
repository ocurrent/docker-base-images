[![OCaml-CI Build Status][ocaml-ci-shield]][ocaml-ci]

This is an [OCurrent][] pipeline that builds Docker images for OCaml, for
various combinations of Linux distribution, Windows version, OCaml version
and architecture.

The resulting images can be run as e.g.

```
docker run --rm -it ocaml/opam:debian-11-ocaml-4.14
```

These images are very similar to the ones previously available as `ocaml/opam2`,
and use the same scripts from [ocurrent/ocaml-dockerfile][].
However, they are much smaller because each image only includes one OCaml compiler.

Each image includes two Dockerfiles showing how it was made:

- `/Dockerfile.opam` is the first stage, which just installs the `opam` binary.
- `/Dockerfile.ocaml` builds on the first stage by installing a particular opam switch.

The service is running at <https://images.ci.ocaml.org/>.

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


[OCurrent]: https://github.com/ocurrent/ocurrent
[pipeline.ml]: https://github.com/ocurrent/docker-base-images/blob/master/src/pipeline.ml
[conf.ml]: https://github.com/ocurrent/docker-base-images/blob/master/src/conf.ml
[ocurrent/ocaml-dockerfile]: https://github.com/ocurrent/ocaml-dockerfile
[OCluster]: https://github.com/ocurrent/ocluster

[ocaml-ci]: https://ocaml.ci.dev/github/ocurrent/docker-base-images
[ocaml-ci-shield]: https://img.shields.io/endpoint?url=https%3A%2F%2Focaml.ci.dev%2Fbadge%2Focurrent%2Fdocker-base-images%2Fmaster&logo=ocaml
