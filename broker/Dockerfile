ARG BUILD_FROM=eclipse-mosquitto:2
FROM ${BUILD_FROM}

# jq to read the add-on options. Install mosquitto + clients explicitly rather
# than assuming the base image provides them on PATH — under the HA add-on
# builder the broker binary wasn't found ("mosquitto: not found"), so pin it here.
RUN apk add --no-cache jq mosquitto mosquitto-clients

COPY mosquitto.conf /etc/openhomepower/mosquitto.conf
COPY aclfile /etc/openhomepower/aclfile
COPY run.sh /run.sh
RUN chmod +x /run.sh

CMD [ "/run.sh" ]
