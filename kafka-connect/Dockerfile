FROM confluentinc/cp-kafka-connect:7.6.0

USER root

RUN confluent-hub install --no-prompt confluentinc/kafka-connect-s3:10.5.7

ENV CONNECT_PLUGIN_PATH=/usr/share/java,/usr/share/confluent-hub-components

USER appuser
