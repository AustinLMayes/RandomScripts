FROM ruby-common

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY ec_live_checker.rb .

# set EC_OUT_DIR
ENV EC_OUT_DIR=/data

RUN mkdir -p /data

CMD ["ruby", "ec_live_checker.rb"]
