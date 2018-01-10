FROM erlang:20.2.2

ENV NDE_ID 1

COPY . /usr/local/src/smsc_simulator

WORKDIR /usr/local/src/smsc_simulator

RUN set -x \
  && rebar3 clean \
  && rebar3 compile \
  && chmod 0755 start.sh

ENTRYPOINT ./start.sh $NDE_ID $(hostname | xargs -n 1 -I hn grep hn /etc/hosts | awk '{print $1}')
