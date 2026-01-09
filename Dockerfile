# syntax=docker/dockerfile:1
FROM ocaml/opam:debian-ocaml-4.14 AS build
RUN sudo ln -sf /usr/bin/opam-2.3 /usr/bin/opam && opam init --reinit -ni
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
RUN cd ~/opam-repository && git fetch -q origin master && git reset --hard a6b2f19780b2edfc4e5dba2566235c877dbf5acd && opam update
RUN opam pin add current.dev git+https://github.com/ocurrent/ocurrent.git -y --no-action && \
    opam pin add current_git.dev git+https://github.com/ocurrent/ocurrent.git -y --no-action && \
    opam pin add current_github.dev git+https://github.com/ocurrent/ocurrent.git -y --no-action && \
    opam pin add current_gitlab.dev git+https://github.com/ocurrent/ocurrent.git -y --no-action && \
    opam pin add current_rpc.dev git+https://github.com/ocurrent/ocurrent.git -y --no-action && \
    opam pin add current_slack.dev git+https://github.com/ocurrent/ocurrent.git -y --no-action && \
    opam pin add current_web.dev git+https://github.com/ocurrent/ocurrent.git -y --no-action && \
    opam pin add current_docker.dev git+https://github.com/ocurrent/ocurrent.git -y --no-action
COPY --chown=opam --link base-images.opam /src/
WORKDIR /src
RUN --mount=type=cache,target=/home/opam/.opam/download-cache,sharing=locked,uid=1000,gid=1000 \
    opam install -y --deps-only .
ADD --chown=opam . .
RUN opam config exec -- dune build ./src/base_images.exe

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
