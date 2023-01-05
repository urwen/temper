# A wrapper to build temper docker
#
# __author__: tuan t. pham

DOCKER_NAME ?=temper
DOCKER_SERVICE_NAME ?=temper/service
DOCKER_TAG ?=latest


docker.service:
	docker build -t $(DOCKER_SERVICE_NAME):$(DOCKER_TAG) .
#docker:
#	docker build -t $(DOCKER_NAME):$(DOCKER_TAG) .
