.PHONY: all

CURDIR=$(shell pwd)

all: bin/mkimage

bin/mkimage: Makefile | bin
	go build -o bin/mkimage src/mkimage/*.go 

bin:
	mkdir -p $@

clean:
	rm -rf bin

.PHONY: test .gofmt .govet .golint

PACKAGES = $(shell go list ./... | grep -v vendor)
test: .gofmt .govet .golint .gotest

.gofmt:
	OUT=$$(go fmt $(PACKAGES)); if test -n "$${OUT}"; then echo "$${OUT}" && exit 1; fi

.govet:
	go vet -x $(PACKAGES)

.golint:
	golint -set_exit_status $(PACKAGES)

.gotest:
	go test $(PACKAGES)
