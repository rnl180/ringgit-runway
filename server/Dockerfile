# Build from the repository root (the server depends on packages/runway_core
# and needs db/migrations):
#   docker build -f server/Dockerfile -t ringgit-runway-api .
FROM dart:stable AS build

WORKDIR /src
COPY packages/runway_core/pubspec.yaml packages/runway_core/
COPY server/pubspec.* server/
RUN cd server && dart pub get

COPY packages/runway_core packages/runway_core
COPY server server
RUN cd server && dart build cli --target bin/server.dart -o output

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /src/server/output/bundle/ /app/
COPY db/migrations /app/db/migrations
ENV MIGRATIONS_DIR=/app/db/migrations

EXPOSE 8080
CMD ["/app/bin/server"]
