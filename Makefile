.PHONY: build-image
build-image:
	docker build --pull -t storjlabs/splunk-s3-tests:latest .

.PHONY: push-image
push-image:
	docker push storjlabs/splunk-s3-tests:latest

.PHONY: clean-image
clean-image:
	# ignore errors during cleanup by preceding commands with dash
	-docker rmi storjlabs/splunk-s3-tests:latest

.PHONY: ci-image-run
ci-image-run:
	# Every Makefile rule is run in its shell, so we need to couple these two so
	# exported credentials are visible to the `docker run ...` command.
	export $$(docker run --network splunk-s3-tests-network-$$BUILD_NUMBER --rm storjlabs/authservice:dev register --address drpc://authservice:20002 --format-env $$(docker exec splunk-s3-tests-sim-$$BUILD_NUMBER storj-sim network env GATEWAY_0_ACCESS)) && \
	docker run \
	--network splunk-s3-tests-network-$$BUILD_NUMBER \
	-e ENDPOINT=gateway:20010 -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e SECURE=0 \
	--name splunk-s3-tests-$$BUILD_NUMBER \
	--rm storjlabs/splunk-s3-tests:latest

.PHONY: ci-network-create
ci-network-create:
	docker network create splunk-s3-tests-network-$$BUILD_NUMBER

.PHONY: ci-network-remove
ci-network-remove:
	-docker network remove splunk-s3-tests-network-$$BUILD_NUMBER

.PHONY: ci-dependencies-start
ci-dependencies-start:
	docker run \
	--network splunk-s3-tests-network-$$BUILD_NUMBER --network-alias postgres \
	-e POSTGRES_DB=sim -e POSTGRES_HOST_AUTH_METHOD=trust \
	--name splunk-s3-tests-postgres-$$BUILD_NUMBER \
	--rm -d postgres:latest

	docker run \
	--network splunk-s3-tests-network-$$BUILD_NUMBER --network-alias redis \
	--name splunk-s3-tests-redis-$$BUILD_NUMBER \
	--rm -d redis:latest

	docker run \
	--network splunk-s3-tests-network-$$BUILD_NUMBER --network-alias sim \
	-e STORJ_SIM_POSTGRES='postgres://postgres@postgres/sim?sslmode=disable' -e STORJ_SIM_REDIS=redis:6379 \
	-v $$PWD/jenkins:/jenkins:ro \
	--name splunk-s3-tests-sim-$$BUILD_NUMBER \
	--rm -d golang:latest /jenkins/start_storj-sim.sh

	# We need to block until storj-sim finishes its build and launches;
	# otherwise, we would pass an invalid satellite ID/address to authservice.
	until docker exec splunk-s3-tests-sim-$$BUILD_NUMBER storj-sim network env SATELLITE_0_URL > /dev/null; do \
		echo "*** storj-sim is not yet available; waiting for 3s..." && sleep 3; \
	done

	docker run \
	--network splunk-s3-tests-network-$$BUILD_NUMBER --network-alias authservice \
	--name splunk-s3-tests-authservice-$$BUILD_NUMBER \
	--rm -d storjlabs/authservice:dev run \
		--listen-addr :20000 \
		--allowed-satellites $$(docker exec splunk-s3-tests-sim-$$BUILD_NUMBER storj-sim network env SATELLITE_0_URL) \
		--auth-token super-secret \
		--endpoint http://gateway:20010 \
		--kv-backend badger:// \
		--node.first-start

	docker run \
	--network splunk-s3-tests-network-$$BUILD_NUMBER --network-alias gateway \
	--name splunk-s3-tests-gateway-$$BUILD_NUMBER \
	--rm -d storjlabs/gateway-mt:dev run \
		--server.address :20010 \
		--auth.base-url http://authservice:20000 \
		--auth.token super-secret \
		--domain-name gateway \
		--insecure-disable-tls \
		--insecure-log-all \
		--s3compatibility.fully-compatible-listing

.PHONY: ci-dependencies-stop
ci-dependencies-stop:
	-docker stop --time=1 $$(docker ps -qf network=splunk-s3-tests-network-$$BUILD_NUMBER)

.PHONY: ci-dependencies-clean
ci-dependencies-clean:
	-docker rmi storjlabs/gateway-mt:dev
	-docker rmi storjlabs/authservice:dev
	-docker rmi golang:latest
	-docker rmi redis:latest
	-docker rmi postgres:latest

.PHONY: ci-run
ci-run: build-image ci-network-create ci-dependencies-start ci-image-run

.PHONY: ci-purge
ci-purge: ci-dependencies-stop ci-dependencies-clean ci-network-remove clean-image
