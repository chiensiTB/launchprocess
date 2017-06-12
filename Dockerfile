# AUTHOR:  Chien Harriman
# DESCRIPTION:  OpenStudio server request handler, that bootstraps the OpenStudio-analysis-spreadsheet

FROM ubuntu:16.04
MAINTAINER Chien Si Harriman chien.harriman@gmail.com

# Replace shell with bash so we can source files
RUN rm /bin/sh && ln -s /bin/bash /bin/sh

# Set environment variables
ENV appDir /var/www/app/current
# ENV spreadsheetDir /var/www/nrelspreadsheet #spreadsheet has been moved to the appDirectory

RUN apt-get update && apt-get install -y \
    autoconf \
    apt-transport-https \
    bison \
    build-essential \
    bzip2 \
    ca-certificates \
    curl \
    default-jdk \
    gdebi-core \
    git \
    libbz2-dev \
    libcurl4-openssl-dev \
    libdbus-glib-1-2 \
    libgdbm3 \
    libgdbm-dev \
    libglib2.0-dev \
    libglu1 \
    libncurses-dev \
    libreadline-dev \
    libxml2-dev \
    libxslt-dev \
        libffi-dev \
        libssl-dev \
        libyaml-dev \
        libice-dev \
        libsm-dev\
        procps \
    ruby \
    sudo \
    tar \
    unzip \
    wget \
    zip \
    zlib1g-dev

# Build and Install Ruby
#   -- skip installing gem documentation
RUN mkdir -p /usr/local/etc \
  && { \
    echo 'install: --no-document'; \
    echo 'update: --no-document'; \
  } >> /usr/local/etc/gemrc

ENV RUBY_MAJOR 2.2
ENV RUBY_VERSION 2.2.4
ENV RUBY_DOWNLOAD_SHA256 b6eff568b48e0fda76e5a36333175df049b204e91217aa32a65153cc0cdcb761
ENV RUBYGEMS_VERSION 2.6.6

# some of ruby's build scripts are written in ruby
# we purge this later to make sure our final image uses what we just built
RUN curl -fSL -o ruby.tar.gz "http://cache.ruby-lang.org/pub/ruby/$RUBY_MAJOR/ruby-$RUBY_VERSION.tar.gz" \
  && echo "$RUBY_DOWNLOAD_SHA256 *ruby.tar.gz" | sha256sum -c - \
  && mkdir -p /usr/src/ruby \
  && tar -xzf ruby.tar.gz -C /usr/src/ruby --strip-components=1 \
  && rm ruby.tar.gz \
  && cd /usr/src/ruby \
  && { echo '#define ENABLE_PATH_CHECK 0'; echo; cat file.c; } > file.c.new && mv file.c.new file.c \
  && autoconf \
  && ./configure --disable-install-doc --enable-shared \
  && make -j"$(nproc)" \
  && make install \
  && apt-get purge -y --auto-remove $buildDeps \
  && gem update --system $RUBYGEMS_VERSION \
  && rm -r /usr/src/ruby

ENV BUNDLER_VERSION 1.11.2

RUN gem install bundler --version "$BUNDLER_VERSION"

# install things globally, for great justice
# and don't create ".bundle" in all our apps
ENV GEM_HOME /usr/local/bundle
ENV BUNDLE_PATH="$GEM_HOME" \
  BUNDLE_BIN="$GEM_HOME/bin" \
  BUNDLE_SILENCE_ROOT_WARNING=1 \
  BUNDLE_APP_CONFIG="$GEM_HOME"
ENV PATH $BUNDLE_BIN:$PATH
RUN mkdir -p "$GEM_HOME" "$BUNDLE_BIN" \
  && chmod 777 "$GEM_HOME" "$BUNDLE_BIN"

# DO I REALLY EVEN NEED THIS
# Install passenger (this also installs nginx)
# ENV PASSENGER_VERSION 5.0.25
# Install Rack. Silly workaround for not having ruby 2.2.2. Rack 1.6.4 is the
# latest for Ruby <= 2.0
# RUN gem install rack -v=1.6.4
# RUN gem install passenger -v $PASSENGER_VERSION
# RUN passenger-install-nginx-module

# Configure the nginx server
# RUN mkdir /var/log/nginx (disable for now)
# ADD nginx.conf /opt/nginx/conf/nginx.conf (disable for now)
# STOP MY LINE OF QUESTIONING

#####Nick's ripoff ends

# Set the spreadsheet directory # this is deprecated, the spreadsheet is now part of the project
# RUN mkdir -p /var/www/nrelspreadsheet
# WORKDIR ${spreadsheetDir}

# alternatively could be exchanged for a local version and COPY
# done as per https://ryanfb.github.io/etc/2015/07/29/git_strategies_for_docker.html
# one line is better 
# RUN git clone https://github.com/chiensiTB/OpenStudio-analysis-spreadsheet.git && cd /var/www/nrelspreadsheet/OpenStudio-analysis-spreadsheet && git checkout fb2d8d5

RUN curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash -
RUN apt-get install -y nodejs 
# TODO could uninstall some build dependencies

# fucking debian installs `node` as `nodejs`
RUN update-alternatives --install /usr/bin/node node /usr/bin/nodejs 10

ENV NVM_DIR /usr/local/nvm
ENV NODE_VERSION 6.1.0

# Install nvm with node and npm
RUN curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.29.0/install.sh | bash \
    && source $NVM_DIR/nvm.sh \
    && nvm install $NODE_VERSION \
    && nvm alias default $NODE_VERSION \
    && nvm use default

# Set up our PATH correctly so we don't have to long-reference npm, node, &c.
ENV NODE_PATH $NVM_DIR/versions/node/v$NODE_VERSION/lib/node_modules
ENV PATH      $NVM_DIR/versions/node/v$NODE_VERSION/bin:$PATH

# Set the node directory
RUN mkdir -p /var/www/app/current
WORKDIR ${appDir}


# Add our package.json and install *before* adding our application files
COPY ./current/package.json $appDir
RUN npm i --production

# Install pm2 so we can run our application
RUN npm i -g pm2

# Add application files
# this should place the files in the appDirectory created above, alternatively could be done with git if repo is available
COPY ./current $appDir

# consider improving for better security
# FLAG! soon no need for these credentials anymore in v2 box
RUN mkdir -p /.aws
COPY credentials /.aws
RUN chmod 755 /.aws/credentials
RUN mkdir -p ~/.aws
COPY credentials ~/.aws
# RUN chmod 755 ~/.aws/credentials

#run the bundle command once inside of the openstudio-analysis-spreadsheet instance to make sure the gems build
RUN cd /var/www/app/current/scripts/OpenStudio-analysis-spreadsheet \
    && bundle install

#expose the right port, it should match what is in app.js
EXPOSE 8080

# change if the command to start node changes
ENTRYPOINT npm run start


