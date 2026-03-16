ARG BASEIMAGE

FROM golang:1.23 AS build

WORKDIR /go/src/karchive
ADD karchive /go/src/karchive
RUN go build  -o /go/bin/karchive cmd/main.go

WORKDIR /go/src/gproxy
ADD gproxy /go/src/gproxy
RUN go build  -o /go/bin/gproxy proxy.go

FROM $BASEIMAGE

RUN rm -f $GOPATH/bin/kubetest2 \
        $GOPATH/bin/kubetest2-gke \
        $GOPATH/bin/kubetest2-tester-exec

RUN go install sigs.k8s.io/kubetest2@latest && \
    go install sigs.k8s.io/kubetest2/kubetest2-gke@latest && \
    go install sigs.k8s.io/kubetest2/kubetest2-tester-exec@latest

COPY --from=build /go/bin/karchive /
COPY --from=build /go/bin/gproxy /

ADD ["https://raw.githubusercontent.com/kubernetes/test-infra/master/logexporter/cluster/log-dump.sh", "/workspace/"]
ENV LOG_DUMP_SCRIPT_PATH "/workspace/log-dump.sh"
RUN ["chmod", "+x", "/workspace/log-dump.sh"]