.PHONY: build tidy docker test clean vendor

GO=CGO_ENABLED=1 go

# see https://shibumi.dev/posts/hardening-executables
CGO_CPPFLAGS="-D_FORTIFY_SOURCE=2"
CGO_CFLAGS="-O2 -pipe -fno-plt"
CGO_CXXFLAGS="-O2 -pipe -fno-plt"
CGO_LDFLAGS="-Wl,-O1,–sort-common,–as-needed,-z,relro,-z,now"

# VERSION file is not needed for local development, In the CI/CD pipeline, a temporary VERSION file is written
# if you need a specific version, just override below
APPVERSION=$(shell cat ./VERSION 2>/dev/null || echo 0.0.0)

# This pulls the version of the SDK from the go.mod file. If the SDK is the only required module,
# it must first remove the word 'required' so the offset of $2 is the same if there are multiple required modules
SDKVERSION=$(shell cat ./go.mod | grep 'github.com/edgexfoundry/app-functions-sdk-go/v3 v' | sed 's/require//g' | awk '{print $$2}')

MICROSERVICE=app-service-configurable
CGOFLAGS=-ldflags "-linkmode=external \
                   -X github.com/edgexfoundry/app-functions-sdk-go/v3/internal.SDKVersion=$(SDKVERSION) \
                   -X github.com/edgexfoundry/app-functions-sdk-go/v3/internal.ApplicationVersion=$(APPVERSION)" \
                   -trimpath -mod=readonly -buildmode=pie

GIT_SHA=$(shell git rev-parse HEAD)

build:
	$(GO) build -tags "$(ADD_BUILD_TAGS)" $(CGOFLAGS) -o $(MICROSERVICE)

build-nats:
	make -e ADD_BUILD_TAGS=include_nats_messaging build

tidy:
	go mod tidy

# NOTE: This is only used for local development. Jenkins CI does not use this make target
docker:
	docker build \
		--build-arg ADD_BUILD_TAGS=$(ADD_BUILD_TAGS) \
	    --build-arg http_proxy \
	    --build-arg https_proxy \
		-f Dockerfile \
		--label "git_sha=$(GIT_SHA)" \
		-t edgexfoundry/app-service-configurable:$(GIT_SHA) \
		-t edgexfoundry/app-service-configurable:${APPVERSION}-dev \
		.

docker-nats:
	make -C . -e ADD_BUILD_TAGS=include_nats_messaging docker

test:
	$(GO) test -coverprofile=coverage.out ./...
	$(GO) vet ./...
	gofmt -l $$(find . -type f -name '*.go'| grep -v "/vendor/")
	[ "`gofmt -l $$(find . -type f -name '*.go'| grep -v "/vendor/")`" = "" ]
	./bin/test-attribution-txt.sh

clean:
	rm -f $(MICROSERVICE)

vendor:
	$(GO) mod vendor
