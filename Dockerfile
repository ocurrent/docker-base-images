# syntax=docker/dockerfile:1
FROM ocaml/opam:debian-13-ocaml-5.4 AS build
RUN sudo ln -sf /usr/bin/opam-2.5 /usr/bin/opam && opam init --reinit -ni
RUN sudo rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' | sudo tee /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    sudo apt update && sudo apt-get --no-install-recommends install -y \
    capnproto \
    graphviz \
    libev-dev \
    libffi-dev \
    libgmp-dev \
    libsqlite3-dev \
    libssl-dev \
    m4 \
    pkg-config
RUN cd ~/opam-repository && git fetch -q origin master && git reset --hard 163a32c4d55fd31c455579249c3437165211f302 && opam update
RUN opam option --global solver=builtin-0install
# OCurrent 2.0 needs the prometheus Eio fork plus all current_* packages
# from the eio branch, and current_ocluster's Eio plugin (which lives on the
# ocluster eio branch alongside its new ocluster-api-eio sibling).
RUN opam pin add -yn prometheus.dev      https://github.com/mtelvers/prometheus.git#eio && \
    opam pin add -yn prometheus-app.dev  https://github.com/mtelvers/prometheus.git#eio && \
    opam pin add -yn current.dev         https://github.com/mtelvers/ocurrent.git#eio && \
    opam pin add -yn current_term.dev    https://github.com/mtelvers/ocurrent.git#eio && \
    opam pin add -yn current_web.dev     https://github.com/mtelvers/ocurrent.git#eio && \
    opam pin add -yn current_git.dev     https://github.com/mtelvers/ocurrent.git#eio && \
    opam pin add -yn current_github.dev  https://github.com/mtelvers/ocurrent.git#eio && \
    opam pin add -yn current_docker.dev  https://github.com/mtelvers/ocurrent.git#eio && \
    opam pin add -yn current_slack.dev   https://github.com/mtelvers/ocurrent.git#eio && \
    opam pin add -yn current_rpc.dev     https://github.com/mtelvers/ocurrent.git#eio && \
    opam pin add -yn ocluster-api-eio.dev https://github.com/mtelvers/ocluster.git#eio && \
    opam pin add -yn current_ocluster.dev https://github.com/mtelvers/ocluster.git#eio
COPY --chown=opam --link base-images.opam /src/
WORKDIR /src
RUN --mount=type=cache,target=/home/opam/.opam/download-cache,sharing=locked,uid=1000,gid=1000 \
    opam install -y --deps-only .
ADD --chown=opam . .
RUN opam exec -- dune build ./src/base_images.exe

FROM debian:13
RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get --no-install-recommends install -y \
    ca-certificates \
    curl \
    git \
    gnupg2 \
    graphviz \
    libev4 \
    libsqlite3-dev \
    docker-cli \
    netbase
COPY --from=build --link /src/_build/default/src/base_images.exe /usr/local/bin/base-images
WORKDIR /var/lib/ocurrent
ENTRYPOINT ["/usr/local/bin/base-images"]
