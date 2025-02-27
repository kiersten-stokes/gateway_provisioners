.PHONY: clean-test clean-pyc clean-build docs help \
	gp-spark-base gp-kernel-py gp-kernel-py gp-kernel-spark-py \
	gp-kernel-r gp-kernel-spark-r gp-kernel-scala
.DEFAULT_GOAL := help

help:
# http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

# extract version from gateway_provisioners/_version.py - override using `make VERSION=foo target`
VERSION?=$(shell grep ^__version__ gateway_provisioners/_version.py | awk '{print $$3}' | sed s'/"//g')

# When building images, where to get the remote-provisioners package: "local" (wheel) or "release" (pip)
PACKAGE_SOURCE?=local

# Docker attributes - hub organization and tag.  Modify accordingly
DOCKER_ORG?=elyra

# Determine TAG from VERSION. If contains "dev", use dev, else VERSION
ifeq (dev, $(findstring dev, $(VERSION)))
    TAG:=dev
else
    TAG:=$(VERSION)
endif

# Set NO_CACHE=--no-cache to force docker build to not use cached layers
NO_CACHE?=

# All ARGs following SPARK_VERSION have values that must correspond to
# that version of Spark.  See https://spark.apache.org/downloads.html
# (OPENJDK_VERSION can be any of 8, 11, 17)
SPARK_VERSION?=3.3.1
SPARK_CHECKSUM?=817f89d83ffacda1c2075d28d4a649bc007a0dd4b8edeac4b2c5e0365efc34fafceff0afedc809faa0e687c6aabf0ff6dbcda329e9045692d700c63018d93171
HADOOP_VERSION?=2
SCALA_VERSION?=2.12
OPENJDK_VERSION?=17


WHEEL_FILES:=$(shell find gateway_provisioners -type f ! -path "*/__pycache__/*" )
WHEEL_FILE:=dist/gateway_provisioners-$(VERSION)-py3-none-any.whl
SDIST_FILE:=dist/gateway_provisioners-$(VERSION).tar.gz
DIST_FILES=$(WHEEL_FILE) $(SDIST_FILE)

TOREE_LAUNCHER_FILES:=$(shell find gateway_provisioners/kernel-launchers/scala/toree-launcher/src -type f -name '*')

WHICH_SBT:=which sbt >> /dev/null

echo-version:
	@echo $(VERSION)

check-sbt:
	@$(WHICH_SBT) || (echo "WARNING: sbt does not appear to be installed, please check https://www.scala-sbt.org/1.x/docs/Setup.html. Continuing...")

clean: clean-build clean-pyc clean-test ## Remove all build, test, coverage, and Python artifacts

clean-build: # Remove build artifacts
	make -C docs clean
	rm -rf build/
	rm -rf dist/
	rm -rf gateway_provisioners/kernel-launchers/scala/lib
	rm -rf gateway_provisioners/kernel-launchers/scala/toree-launcher/target
	rm -rf gateway_provisioners/kernel-launchers/scala/toree-launcher/project/target
	rm -rf .eggs/
	find . -name '*.egg-info' -exec rm -rf {} +
	find . -name '*.egg' -exec rm -f {} +

clean-pyc: # Remove Python file artifacts (pyc files, __pycache__, etc.)
	find . -name '*.pyc' -exec rm -f {} +
	find . -name '*.pyo' -exec rm -f {} +
	find . -name '*~' -exec rm -f {} +
	find . -name '__pycache__' -exec rm -rf {} +

clean-test: # Remove test and coverage artifacts
	rm -f .coverage
	rm -rf htmlcov/
	rm -rf .pytest_cache

lint: ## Check style and linting
	hatch run lint:style

lint-fix: ## Run lint with updates enabled
	hatch run lint:fmt

test: ## Run tests with the currently active Python version
	hatch run test:test

docs: ## Generate Sphinx HTML documentation, including API docs
	hatch run docs:api
	hatch run docs:build

release: dist ## Package and upload a release using twine
	twine upload dist/*

dist: wheel sdist  ## Build wheel and source distributions
	ls -l dist

sdist: $(SDIST_FILE)

$(SDIST_FILE): $(WHEEL_FILES)
	python -m build --sdist

wheel: gateway_provisioners/kernel-launchers/scala/lib $(WHEEL_FILE)

$(WHEEL_FILE): $(WHEEL_FILES)
	python -m build --wheel

install: clean wheel ## Install the package to the active Python's site-packages
	pip uninstall -y remote-provisioners
	pip install dist/gateway_provisioners-*.whl

gateway_provisioners/kernel-launchers/scala/lib: $(TOREE_LAUNCHER_FILES)
	-rm -rf gateway_provisioners/kernel-launchers/scala/lib
	mkdir -p gateway_provisioners/kernel-launchers/scala/lib
	@(cd gateway_provisioners/kernel-launchers/scala/toree-launcher; sbt -Dversion=$(VERSION) package; cp target/scala-2.12/*.jar ../lib)

BASE_IMAGES := gp-spark-base
KERNEL_IMAGES := gp-kernel-py gp-kernel-spark-py gp-kernel-r gp-kernel-spark-r gp-kernel-scala
DOCKER_IMAGES := $(BASE_IMAGES) $(KERNEL_IMAGES)

base-images: $(BASE_IMAGES)
kernel-images: $(KERNEL_IMAGES)
images: $(DOCKER_IMAGES)  ## Build all docker images.  Targets base-images and kernel-images can also be used.
clean-base-images: clean-gp-spark-base
clean-kernel-images: clean-gp-kernel-py clean-gp-kernel-spark-py clean-gp-kernel-r clean-gp-kernel-spark-r clean-gp-kernel-scala
clean-images: clean-base-images clean-kernel-images  ## Remove all docker images.  Targets clean-base-images and clean-kernel-images can also be used.
push-base-images: push-gp-spark-base
push-kernel-images: push-gp-kernel-py push-gp-kernel-spark-py push-gp-kernel-r push-gp-kernel-spark-r push-gp-kernel-scala
push-images: push-base-images push-kernel-images  ## Push all docker images.  Targets push-base-images and push-kernel-images can also be used.

# Location to find docker files used in build
DOCKER_gp-spark-base := gateway_provisioners/docker/gp-spark-base
DOCKER_gp-kernel-py := gateway_provisioners/docker/kernel-image
DOCKER_gp-kernel-spark-py := gateway_provisioners/docker/kernel-image
DOCKER_gp-kernel-r := gateway_provisioners/docker/kernel-image
DOCKER_gp-kernel-spark-r := gateway_provisioners/docker/kernel-image
DOCKER_gp-kernel-scala := gateway_provisioners/docker/kernel-image

#
BUILD_ARGS_gp-spark-base := --build-arg SPARK_VERSION=${SPARK_VERSION} --build-arg HADOOP_VERSION=${HADOOP_VERSION} \
	--build-arg SCALA_VERSION=${SCALA_VERSION} --build-arg OPENJDK_VERSION=${OPENJDK_VERSION} \
	--build-arg SPARK_CHECKSUM=${SPARK_CHECKSUM}
BUILD_ARGS_gp-kernel-py := --build-arg PACKAGE_SOURCE=${PACKAGE_SOURCE} --build-arg KERNEL_LANG=python
BUILD_ARGS_gp-kernel-spark-py := ${BUILD_ARGS_gp-kernel-py} --build-arg BASE_CONTAINER=${DOCKER_ORG}/gp-spark-base:$(TAG)
BUILD_ARGS_gp-kernel-r := --build-arg PACKAGE_SOURCE=${PACKAGE_SOURCE} --build-arg KERNEL_LANG=r
BUILD_ARGS_gp-kernel-spark-r := ${BUILD_ARGS_gp-kernel-r} --build-arg BASE_CONTAINER=${DOCKER_ORG}/gp-spark-base:$(TAG)
BUILD_ARGS_gp-kernel-scala := --build-arg PACKAGE_SOURCE=${PACKAGE_SOURCE} --build-arg KERNEL_LANG=scala --build-arg BASE_CONTAINER=${DOCKER_ORG}/gp-spark-base:$(TAG)

# Extra (besides docker files) dependencies for each docker image...
DEPENDS_gp-spark-base :=
DEPENDS_gp-kernel-py := $(WHEEL_FILE)
DEPENDS_gp-kernel-spark-py := $(WHEEL_FILE)
DEPENDS_gp-kernel-r := $(WHEEL_FILE)
DEPENDS_gp-kernel-spark-r := $(WHEEL_FILE)
DEPENDS_gp-kernel-scala := $(WHEEL_FILE)

# Extra targets for each image
TARGETS_gp-spark-base:
TARGETS_gp-kernel-py TARGETS_gp-kernel-py TARGETS_gp-kernel-spark-py TARGETS_gp-kernel-r \
	TARGETS_gp-kernel-spark-r TARGETS_gp-kernel-scala: wheel $(BASE_IMAGES)

# Generate image creation targets for each entry in $(DOCKER_IMAGES).  Switch 'eval' to 'info' to see what is produced.
define BUILD_IMAGE
$1: .image-$1
.image-$1: $$(DOCKER_$1)/* $$(DEPENDS_$1)
	@make clean-$1 TARGETS_$1
	@mkdir -p build/docker/$1
	@cp -r $$(DOCKER_$1)/* $$(DEPENDS_$1) build/docker/$1
	(cd build/docker/$1; \
				docker build ${NO_CACHE} \
					--build-arg DOCKER_ORG=${DOCKER_ORG} \
					$$(BUILD_ARGS_$1) \
					-t $(DOCKER_ORG)/$1:$(TAG) .\
	)
	@touch .image-$1
	@-docker images $(DOCKER_ORG)/$1:$(TAG)
endef
$(foreach image,$(DOCKER_IMAGES),$(eval $(call BUILD_IMAGE,$(image))))

# Generate clean-xxx targets for each entry in $(DOCKER_IMAGES).  Switch 'eval' to 'info' to see what is produced.
define CLEAN_IMAGE
clean-$1:
	@rm -f .image-$1
	@-docker rmi -f $(DOCKER_ORG)/$1:$(TAG)
endef
$(foreach image,$(DOCKER_IMAGES),$(eval $(call CLEAN_IMAGE,$(image))))

# Publish each publish image on $(PUSHED_IMAGES) to DockerHub.  Switch 'eval' to 'info' to see what is produced.
define PUSH_IMAGE
push-$1:
	docker push $(DOCKER_ORG)/$1:$(TAG)
endef
$(foreach image,$(PUSHED_IMAGES),$(eval $(call PUSH_IMAGE,$(image))))
