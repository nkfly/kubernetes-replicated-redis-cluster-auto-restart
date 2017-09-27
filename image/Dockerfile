# Pull base image.
FROM ubuntu:16.04

MAINTAINER Liyuan Hung <nkflyfly@gmail.com>

RUN apt-get update
RUN apt-get install -y wget jq ruby cmake curl

RUN gem install redis

# Install Redis.
RUN \
  cd /tmp && \
  wget http://download.redis.io/redis-stable.tar.gz && \
  tar xvzf redis-stable.tar.gz && \
  cd redis-stable && \
  make && \
  make install && \
  cp -f src/redis-sentinel /usr/local/bin && \
  mkdir -p /etc/redis && \
  cp -f *.conf /etc/redis && \
  rm -rf /tmp/redis-stable* && \
  sed -i 's/^\(bind .*\)$/# \1/' /etc/redis/redis.conf && \
  sed -i 's/^\(daemonize .*\)$/# \1/' /etc/redis/redis.conf && \
  sed -i 's/^\(dir .*\)$/# \1\ndir \/data/' /etc/redis/redis.conf && \
  sed -i 's/^\(logfile .*\)$/# \1/' /etc/redis/redis.conf

# Define mountable directories.
VOLUME ["/data"]

# Define working directory.
WORKDIR /data

ADD ./docker-entrypoint.sh /docker-entrypoint.sh
ADD ./redis.conf /etc/redis/redis.conf
ADD ./redis-trib.rb /redis-trib.rb

# Define default command.
CMD ["/docker-entrypoint.sh"]

# Expose ports.
EXPOSE 6379
