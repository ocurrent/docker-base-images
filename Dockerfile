FROM ocurrent/opam:debian-10-ocaml-4.10@sha256:b8683f4ddd6ec3fc979637e9e8140b0f6fc67e48f6913e73bbc4311dfb8dd130 AS build
RUN sudo apt-get update && sudo apt-get install capnproto graphviz m4 pkg-config libsqlite3-dev libgmp-dev libssl-dev -y --no-install-recommends
RUN cd ~/opam-repository && git pull origin master && git reset --hard 58d97b2c265c368952a50355247bb28a8ab1f597 && opam update
COPY --chown=opam \
	ocurrent/current.opam \
	ocurrent/current_web.opam \
	ocurrent/current_ansi.opam \
	ocurrent/current_docker.opam \
	ocurrent/current_git.opam \
	ocurrent/current_github.opam \
	ocurrent/current_incr.opam \
	ocurrent/current_slack.opam \
	ocurrent/current_rpc.opam \
	/src/ocurrent/
WORKDIR /src
RUN opam pin add -yn current_ansi.dev "./ocurrent" && \
    opam pin add -yn current_docker.dev "./ocurrent" && \
    opam pin add -yn current_git.dev "./ocurrent" && \
    opam pin add -yn current_github.dev "./ocurrent" && \
    opam pin add -yn current_incr.dev "./ocurrent" && \
    opam pin add -yn current.dev "./ocurrent" && \
    opam pin add -yn current_rpc.dev "./ocurrent" && \
    opam pin add -yn current_slack.dev "./ocurrent" && \
    opam pin add -yn current_web.dev "./ocurrent"
COPY --chown=opam base-images.opam /src/
RUN opam install -y --deps-only .
ADD --chown=opam . .
RUN opam config exec -- dune build ./src/base_images.exe

FROM debian:10
RUN apt-get update && apt-get install openssh-client curl dumb-init git graphviz libsqlite3-dev ca-certificates netbase -y --no-install-recommends
RUN apt-get install gnupg2 -y --no-install-recommends
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
RUN echo 'deb [arch=amd64] https://download.docker.com/linux/debian buster stable' >> /etc/apt/sources.list
RUN apt-get update && apt-get install docker-ce -y --no-install-recommends
RUN mkdir /root/.ssh && chmod 0700 /root/.ssh && ln -s /run/secrets/ocurrent-ssh-key /root/.ssh/id_rsa
COPY known_hosts /root/.ssh/known_hosts
COPY dot_docker /root/.docker
COPY --from=build /src/_build/default/src/base_images.exe /usr/local/bin/base-images
WORKDIR /var/lib/ocurrent
ENTRYPOINT ["dumb-init", "/usr/local/bin/base-images"]
