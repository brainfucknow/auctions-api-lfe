# Build and run the auctions release.
#
# The release does not bundle ERTS (include_erts is false), so the runtime
# stage is the same Erlang image as the build stage rather than a bare distro.
# No git is needed: the app version is literal and hex deps are tarballs.

FROM erlang:28-slim AS build

WORKDIR /src
COPY rebar.config rebar.lock ./
COPY include include
COPY src src
COPY config config

RUN rebar3 as prod release

FROM erlang:28-slim AS runtime

# vm.args enables distribution, so the service user needs a home directory for
# the Erlang cookie; without it the node dies before kernel finishes starting.
RUN useradd --system --create-home --home-dir /home/auctions auctions \
 && mkdir -p /var/lib/auctions \
 && chown auctions:auctions /var/lib/auctions

COPY --from=build /src/_build/prod/rel/auctions /opt/auctions

USER auctions
ENV HOME=/home/auctions
VOLUME ["/var/lib/auctions"]
EXPOSE 8080

# The event log lives on the volume; see config/sys.config.
CMD ["/opt/auctions/bin/auctions", "foreground"]
