DEPS := "wget git go docker golint"

BINARY := autospotting
BINARY_PKG := ./core
GOFILES := $(shell find . -type f -name '*.go' -not -path "./vendor/*")
COVER_PROFILE := /tmp/coverage.out
BUCKET_NAME ?= cloudprowess
FLAVOR ?= custom
LOCAL_PATH := build/s3/$(FLAVOR)

SHA := $(shell git rev-parse HEAD | cut -c 1-7)
BUILD := $(or $(TRAVIS_BUILD_NUMBER), $(TRAVIS_BUILD_NUMBER), $(SHA))

LDFLAGS="-X main.Version=$(FLAVOR)-$(BUILD)"

all: fmt-check vet-check build test                          ## Build the code
.PHONY: all

clean:                                                       ## Remove installed packages/temporary files
	go clean ./...
	rm -rf $(BINDATA_DIR) $(LOCAL_PATH)
.PHONY: clean

check_deps:                                                  ## Verify the system has all dependencies installed
	@for DEP in "$(DEPS)"; do \
		if ! command -v "$$DEP" >/dev/null ; then echo "Error: dependency '$$DEP' is absent" ; exit 1; fi; \
	done
	@echo "all dependencies satisifed: $(DEPS)"
.PHONY: check_deps

build_deps:
	@go get github.com/mattn/goveralls
	@go get github.com/golang/lint/golint
	@go get golang.org/x/tools/cmd/cover
.PHONY: build_deps

build: build_deps                                            ## Build autospotting binary
	GOOS=linux go build -ldflags=$(LDFLAGS) -o $(BINARY)
.PHONY: build

archive: build                                               ## Create archive to be uploaded
	@rm -rf $(LOCAL_PATH)
	@mkdir -p $(LOCAL_PATH)
	@zip $(LOCAL_PATH)/lambda.zip $(BINARY)
	@cp -f cloudformation/stacks/AutoSpotting/template.json $(LOCAL_PATH)/template.json
	@cp -f cloudformation/stacks/AutoSpotting/template.json $(LOCAL_PATH)/template_build_$(BUILD).json
	@cp -f $(LOCAL_PATH)/lambda.zip $(LOCAL_PATH)/lambda_build_$(BUILD).zip
	@cp -f $(LOCAL_PATH)/lambda.zip $(LOCAL_PATH)/lambda_build_$(SHA).zip
.PHONY: archive

upload: archive                                              ## Upload binary
	aws s3 sync build/s3/ s3://$(BUCKET_NAME)/
.PHONY: upload

vet-check:                                                   ## Verify vet compliance
ifeq ($(shell go tool vet -all -shadow=true $(GOFILES) 2>&1 | wc -l), 0)
	@printf "ok\tall files passed go vet\n"
else
	@printf "error\tsome files did not pass go vet\n"
	@go tool vet -all -shadow=true $(GOFILES) 2>&1
endif
.PHONY: vet-check

fmt-check:                                                   ## Verify fmt compliance
ifneq ($(shell gofmt -l -s $(GOFILES) | wc -l), 0)
	@printf "error\tsome files did not pass go fmt, fix the following formatting diff:\n"
	@gofmt -l -s -d $(GOFILES)
	@exit 1
else
	@printf "ok\tall files passed go fmt\n"
endif
.PHONY: fmt-check

test:                                                        ## Test go code and coverage
	@go test -covermode=count -coverprofile=$(COVER_PROFILE) $(BINARY_PKG)
.PHONY: test

lint:
	@golint -set_exit_status $(BINARY_PKG)
	@golint -set_exit_status .
.PHONY: lint

full-test: fmt-check vet-check test lint                     ## Pass test / fmt / vet / lint
.PHONY: full-test

html-cover: test                                             ## Display coverage in HTML
	@go tool cover -html=$(COVER_PROFILE)
.PHONY: html-cover

travisci-cover: html-cover                                   ## Test & generate coverage in the TravisCI format, fails unless executed from TravisCI
	@goveralls -coverprofile=$(COVER_PROFILE) -service=travis-ci
.PHONY: travisci-cover

travisci-checks: fmt-check vet-check lint                    ## Pass fmt / vet & lint format
.PHONY: travisci-checks

travisci: archive travisci-checks travisci-cover             ## Executed by TravisCI
.PHONY: travisci

help:                                                        ## Show this help
	@printf "Rules:\n"
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##//'
.PHONY: help
