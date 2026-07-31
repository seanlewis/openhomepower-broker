ARG BUILD_FROM=eclipse-mosquitto:2
FROM ${BUILD_FROM}

# jq to read the add-on options; mosquitto + clients are in the base image.
RUN apk add --no-cache jq

COPY mosquitto.conf /etc/openhomepower/mosquitto.conf
COPY aclfile /etc/openhomepower/aclfile
COPY run.sh /run.sh
RUN chmod +x /run.sh

CMD [ "/run.sh" ]
