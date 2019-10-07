FROM ocaml/opam2:debian-10-ocaml-4.08 AS build
RUN sudo apt-get update && sudo apt-get install capnproto graphviz m4 pkg-config libsqlite3-dev libgmp-dev -y --no-install-recommends
RUN cd ~/opam-repository && git pull origin master && git reset --hard 8bc187ff7168b47537d5bbd9b330a90ed90830ad && opam update
COPY --chown=opam \
	ocurrent/current.opam \
	ocurrent/current_web.opam \
	ocurrent/current_ansi.opam \
	ocurrent/current_docker.opam \
	ocurrent/current_git.opam \
	ocurrent/current_slack.opam \
	ocurrent/current_rpc.opam \
	/src/ocurrent/
RUN opam pin -y add /src/ocurrent
COPY --chown=opam base-images.opam /src/
WORKDIR /src
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
