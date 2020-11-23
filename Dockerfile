ARG goversion=1.13

FROM teamserverless/license-check:0.3.9 as license-check

FROM --platform=${BUILDPLATFORM:-linux/amd64} golang:$goversion as builder

ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG TARGETOS
ARG TARGETARCH

ARG GIT_COMMIT="000000"
ARG VERSION="dev"

ENV CGO_ENABLED=0
ENV GO111MODULE=off

COPY --from=license-check /license-check /usr/bin/

RUN mkdir -p /go/src/github.com/openfaas-incubator/mqtt-connector
WORKDIR /go/src/github.com/openfaas-incubator/mqtt-connector

COPY . .

ARG OPTS
# RUN go mod download

RUN gofmt -l -d $(find . -type f -name '*.go' -not -path "./vendor/*")
RUN go test -v ./...
RUN VERSION=$(git describe --all --exact-match `git rev-parse HEAD` | grep tags | sed 's/tags\///') && \
  GIT_COMMIT=$(git rev-list -1 HEAD) && \
  env ${OPTS} CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -ldflags "-s -w \
  -X github.com/openfaas-incubator/mqtt-connector/pkg/version.Release=${VERSION} \
  -X github.com/openfaas-incubator/mqtt-connector/pkg/version.SHA=${GIT_COMMIT}" \
  -a -installsuffix cgo -o connector . && \
  addgroup --system app && \
  adduser --system --ingroup app app && \
  mkdir /scratch-tmp

# we can't add user in next stage because it's from scratch
# ca-certificates and tmp folder are also missing in scratch
# so we add all of it here and copy files in next stage

FROM scratch

COPY --from=builder /etc/passwd /etc/group /etc/
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder --chown=app:app /scratch-tmp /tmp/
COPY --from=builder /go/src/github.com/openfaas-incubator/mqtt-connector/connector /usr/bin/connector

USER app

CMD ["/usr/bin/connector"]
