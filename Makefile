#GIT_VERSION := $(shell git describe --tags)
#VERSION := $(shell cat VERSION)

GIT_VERSION := 3.7.1
VERSION := 3.7.1
GO_PREFIX := github.com/carbonblack/cb-event-forwarder
EL_VERSION := $(shell rpm -E %{rhel})
TARGET_OS=linux
export GO111MODULE=on

# non-release builds include a timestamp in the RPM name
# use "RELEASE=1 make rpm" for a release build, which will not use the timestamp
# RELEASE has a default value of 0
RELEASE ?= 0

.PHONY: clean test rpmbuild rpminstall build rpm

cb-event-forwarder: build

compile-protobufs:
	go get -u github.com/gogo/protobuf/protoc-gen-gogofast
	go mod tidy
	protoc --gogofast_out=.  ./cmd/cb-event-forwarder/sensor_events.proto
	sed -i 's/package sensor_events/package main/g' ./cmd/cb-event-forwarder/sensor_events.pb.go

build-no-static: compile-protobufs
	go mod verify
	go build ./cmd/cb-event-forwarder
	go build ./cmd/kafka-util

build: compile-protobufs
	go mod verify
	go build -tags static ./cmd/cb-event-forwarder
	go build -tags static ./cmd/kafka-util

rpmbuild:
	go get -u github.com/gogo/protobuf/protoc-gen-gogofast
	protoc --gogofast_out=.  ./cmd/cb-event-forwarder/sensor_events.proto
	sed -i 's/package sensor_events/package main/g' ./cmd/cb-event-forwarder/sensor_events.pb.go
	go build -tags static -ldflags "-X main.version=${VERSION}" ./cmd/cb-event-forwarder
	go build -tags static -ldflags "-X main.version=${VERSION}" ./cmd/kafka-util

rpminstall:
	mkdir -p ${RPM_BUILD_ROOT}/usr/share/cb/integrations/event-forwarder
	cp -p cb-event-forwarder ${RPM_BUILD_ROOT}/usr/share/cb/integrations/event-forwarder/cb-event-forwarder
	cp -p kafka-util ${RPM_BUILD_ROOT}/usr/share/cb/integrations/event-forwarder/kafka-util
	cp -p cb-edr-fix-permissions.sh ${RPM_BUILD_ROOT}/usr/share/cb/integrations/event-forwarder/cb-edr-fix-permissions.sh
	mkdir -p ${RPM_BUILD_ROOT}/etc/cb/integrations/event-forwarder
	cp -p conf/cb-event-forwarder.example.ini ${RPM_BUILD_ROOT}/etc/cb/integrations/event-forwarder/cb-event-forwarder.conf
ifeq (${EL_VERSION},6)
	mkdir -p ${RPM_BUILD_ROOT}/etc/init.d
	cp -p init-scripts/cb-event-forwarder ${RPM_BUILD_ROOT}/etc/init.d/cb-event-forwarder
	chmod 755 ${RPM_BUILD_ROOT}/etc/init.d/cb-event-forwarder
else
	mkdir -p ${RPM_BUILD_ROOT}/etc/systemd/system
	cp -p cb-event-forwarder.service ${RPM_BUILD_ROOT}/etc/systemd/system/cb-event-forwarder.service
endif
	mkdir -p ${RPM_BUILD_ROOT}/usr/share/cb/integrations/event-forwarder/content
	cp -rp static/* ${RPM_BUILD_ROOT}/usr/share/cb/integrations/event-forwarder/content

test:
	rm -rf test_output/gold_output
	rm -rf test_output/go_output
	rm -rf test_output/leef_output
	mkdir test_output/gold_output
	python test/scripts/process_events_python.py test/raw_data test_output/gold_output
	go test ./cmd/cb-event-forwarder
	PYTHONIOENCODING=utf8 python test/scripts/compare_outputs.py test_output/gold_output test_output/go_output > test_output/output.txt

clean:
	rm -f cb-event-forwarder
	rm -rf test_output/gold_output
	rm -rf test_output/go_output
	rm -rf dist
	rm -rf build
	rm -f VERSION

bench:
	go test -bench=. ./cmd/cb-event-forwarder/

sdist:
	$(info RELEASE is ${RELEASE})
	mkdir -p build/cb-event-forwarder-${GIT_VERSION}/src/${GO_PREFIX}
	echo "${GIT_VERSION}" > build/cb-event-forwarder-${GIT_VERSION}/VERSION
	cp -rp cb-event-forwarder cb-edr-fix-permissions.sh cb-event-forwarder.service Makefile go.mod cmd static conf init-scripts build/cb-event-forwarder-${GIT_VERSION}/src/${GO_PREFIX}
	cp -rp MANIFEST${EL_VERSION} build/cb-event-forwarder-${GIT_VERSION}/MANIFEST
	(cd build; tar -cz -f cb-event-forwarder-${GIT_VERSION}.tar.gz cb-event-forwarder-${GIT_VERSION})
	sleep 1
	mkdir -p dist
	cp -p build/cb-event-forwarder-${GIT_VERSION}.tar.gz dist/

rpm: sdist
	mkdir -p ${HOME}/rpmbuild/SOURCES
	cp -p dist/cb-event-forwarder-${GIT_VERSION}.tar.gz ${HOME}/rpmbuild/SOURCES/
	rpmbuild -v --define 'release_pkg ${RELEASE}' --define 'version ${GIT_VERSION}' --define 'release 1' -bb cb-event-forwarder.rpm.spec
