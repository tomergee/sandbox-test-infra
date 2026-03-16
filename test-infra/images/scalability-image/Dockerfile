ARG BASEIMAGE

FROM golang:1.23 AS build
WORKDIR /go/src/karchive
ADD karchive /go/src/karchive
RUN go build  -o /go/bin/karchive cmd/main.go

WORKDIR /go/src/gproxy
ADD gproxy /go/src/gproxy
RUN go build  -o /go/bin/gproxy proxy.go

FROM $BASEIMAGE
COPY --from=build /go/bin/karchive /
COPY --from=build /go/bin/gproxy /
