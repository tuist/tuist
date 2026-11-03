FROM busybox:1.36
ARG SEED
RUN echo "$SEED" > /seed && head -c 200000000 /dev/urandom > /layer1
RUN head -c 200000000 /dev/urandom > /layer2
RUN head -c 200000000 /dev/urandom > /layer3
