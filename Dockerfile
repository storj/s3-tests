FROM python:2

WORKDIR /s3-tests

RUN apt-get install -y libevent-dev libxml2-dev libxslt-dev zlib1g-dev
COPY . .

RUN pip install --upgrade pip
RUN pip install -r requirements.txt

# bypass the bootstrap script that uses virtualenv, which isn't necessary since
# we're in a container with all dependencies installed directly
RUN python setup.py develop

ENV S3TEST_CONF=/s3-tests/splunk.conf

ENTRYPOINT ["nosetests"]
CMD ["-a", "!skip_for_splunk,!skip_for_storj"]
