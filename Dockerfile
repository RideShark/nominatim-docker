# -*-dockerfile-*-

FROM phusion/baseimage@sha256:29479c37fcb28089eddd6619deed43bcdbcccf2185369e0199cc51a5ec78991b
LABEL maintainer Bryan Rayner <bryan@rideshark.com>

# Use bash
RUN rm /bin/sh && ln -s /bin/bash /bin/sh

# Update image
RUN apt-get -qq update && apt-get -qq upgrade -y -o \
      Dpkg::Options::="--force-confold"

# Update locales
USER root
RUN apt-get install -y --no-install-recommends locales
ENV DEBIAN_FRONTEND noninteractive
ENV LANG C.UTF-8
RUN locale-gen en_US.UTF-8
RUN update-locale LANG=en_US.UTF-8

# Add postgresql sources
USER root
RUN apt-get install -y --no-install-recommends wget
RUN echo "deb http://apt.postgresql.org/pub/repos/apt xenial-pgdg main" >> \
      /etc/apt/sources.list && \
    wget --quiet -O - http://apt.postgresql.org/pub/repos/apt/ACCC4CF8.asc | \
      apt-key add -
RUN apt-get -qq --fix-missing update

# Set build variables
ARG PGSQL_VERSION=9.6
ARG POSTGIS_VERSION=2.4

# Install build dependencies
USER root
RUN apt-get install -y --no-install-recommends --fix-missing \
      apache2 \
      build-essential \
      ca-certificates \
      cmake \
      curl \
      g++ \
      git \
      libapache2-mod-php \
      libboost-dev \
      libboost-filesystem-dev \
      libboost-python-dev \
      libboost-system-dev \
      libbz2-dev \
      libexpat1-dev \
      libgeos-dev \
      libgeos++-dev \
      libpq-dev \
      libproj-dev \
      libxml2-dev\
      openssl \
      osmosis \
      php \
      php-db \
      php-intl \
      php-pear \
      php-pgsql \
      postgresql-${PGSQL_VERSION}-postgis-${POSTGIS_VERSION} \
      postgresql-${PGSQL_VERSION}-postgis-${POSTGIS_VERSION}-scripts \
      postgresql-contrib-${PGSQL_VERSION} \
      postgresql-server-dev-${PGSQL_VERSION} \
      python \
      python-pip \
      python-setuptools \
      sudo \
      zlib1g-dev
RUN pip install --upgrade pip
RUN pip install osmium

RUN pip install psycopg2

RUN apt-get install -y python3-pip
RUN pip3 install psycopg2


# Create nominatim user account
USER root
RUN useradd -d /srv/nominatim -s /bin/bash -m nominatim
ENV USERNAME nominatim
ENV USERHOME /srv/nominatim
RUN chmod a+x ${USERHOME}

# Install Nominatim
USER nominatim
ARG REPLICATION_URL=https://planet.osm.org/replication/hour/
WORKDIR /srv/nominatim
RUN git clone --recursive git://github.com/openstreetmap/Nominatim.git
RUN echo $'<?php\n\
      # Paths
      @define('CONST_Postgresql_Version', '${PGSQL_VERSION}'); \n\
      @define('CONST_Postgis_Version', '${POSTGIS_VERSION}'); \n\
      @define('CONST_Osm2pgsql_Flatnode_File', '/srv/nominatim/flatnode'); \n\
      @define('CONST_Pyosmium_Binary', '/usr/local/bin/pyosmium-get-changes'); \n\
      # Website settings
      @define('CONST_Website_BaseURL', '/nominatim/'); \n\
      @define('CONST_Replication_Url', '${REPLICATION_URL}'); \n\
      @define('CONST_Replication_MaxInterval', '86400'); \n\
      @define('CONST_Replication_Update_Interval', '86400'); \n\
      @define('CONST_Replication_Recheck_Interval', '900'); \n'\
    > ./Nominatim/settings/local.php
RUN wget -O Nominatim/data/country_osm_grid.sql.gz \
      http://www.nominatim.org/data/country_grid.sql.gz
RUN mkdir ${USERHOME}/Nominatim/build && \
    cd ${USERHOME}/Nominatim/build && \
    cmake ${USERHOME}/Nominatim && \
    make

# Download data for initial import
USER nominatim
## ARG PBF_URL=https://planet.osm.org/pbf/planet-latest.osm.pbf
## RUN curl -L ${PBF_URL} --create-dirs -o /srv/nominatim/src/data.osm.pbf
RUN curl -L http://download.geofabrik.de/africa-latest.osm.pbf --create-dirs -o /srv/nominatim/src/africa.osm.pbf && \
    curl -L http://download.geofabrik.de/antarctica-latest.osm.pbf --create-dirs -o /srv/nominatim/src/antarctica.osm.pbf && \
    curl -L http://download.geofabrik.de/asia-latest.osm.pbf --create-dirs -o /srv/nominatim/src/asia.osm.pbf && \
    curl -L http://download.geofabrik.de/australia-oceania-latest.osm.pbf --create-dirs -o /srv/nominatim/src/australia.osm.pbf && \
    curl -L http://download.geofabrik.de/central-america-latest.osm.pbf --create-dirs -o /srv/nominatim/src/central-america.osm.pbf && \
    curl -L http://download.geofabrik.de/europe-latest.osm.pbf --create-dirs -o /srv/nominatim/src/europe.osm.pbf && \
    curl -L http://download.geofabrik.de/north-america-latest.osm.pbf --create-dirs -o /srv/nominatim/src/north-america.osm.pbf && \
    curl -L http://download.geofabrik.de/south-america-latest.osm.pbf --create-dirs -o /srv/nominatim/src/south-america.osm.pbf

USER root
# Install OSMCtools to combine multiple pbf files into one.
RUN apt-get install osmctools

USER nominatim
RUN osmconvert -v --statistics /srv/nominatim/src/africa.osm.pbf -o=/srv/nominatim/src/africa.o5m && \
    osmconvert -v --statistics /srv/nominatim/src/antarctica.osm.pbf -o=/srv/nominatim/src/antarctica.o5m && \
    osmconvert -v --statistics /srv/nominatim/src/asia.osm.pbf -o=/srv/nominatim/src/asia.o5m && \
    osmconvert -v --statistics /srv/nominatim/src/australia.osm.pbf -o=/srv/nominatim/src/australia.o5m && \
    osmconvert -v --statistics /srv/nominatim/src/central-america.osm.pbf -o=/srv/nominatim/src/central-america.o5m && \
    osmconvert -v --statistics /srv/nominatim/src/europe.osm.pbf -o=/srv/nominatim/src/europe.o5m && \
    osmconvert -v --statistics /srv/nominatim/src/north-america.osm.pbf -o=/srv/nominatim/src/north-america.o5m && \
    osmconvert -v --statistics /srv/nominatim/src/south-america.osm.pbf -o=/srv/nominatim/src/south-america.o5m && \
    osmconvert -v --statistics /srv/nominatim/src/africa.o5m /srv/nominatim/src/antarctica.o5m /srv/nominatim/src/asia.o5m /srv/nominatim/src/australia.o5m /srv/nominatim/src/central-america.o5m /srv/nominatim/src/europe.o5m /srv/nominatim/src/north-america.o5m /srv/nominatim/src/south-america.o5m -o=/srv/nominatim/src/allcountries.o5m
RUN osmconvert -v --statistics /srv/nominatim/src/allcountries.o5m -o=/srv/nominatim/src/data.osm.pbf
RUN rm /srv/nominatim/src/africa.osm.pbf /srv/nominatim/src/africa.o5m \
    /srv/nominatim/src/antarctica.osm.pbf /srv/nominatim/src/antarctica.o5m \
    /srv/nominatim/src/asia.osm.pbf /srv/nominatim/src/asia.o5m \
    /srv/nominatim/src/australia.osm.pbf /srv/nominatim/src/australia.o5m \
    /srv/nominatim/src/central-america.osm.pbf /srv/nominatim/src/central-america.o5m \
    /srv/nominatim/src/europe.osm.pbf /srv/nominatim/src/europe.o5m \
    /srv/nominatim/src/north-america.osm.pbf /srv/nominatim/src/north-america.o5m \
    /srv/nominatim/src/south-america.osm.pbf /srv/nominatim/src/south-america.o5m \
    /srv/nominatim/src/allcountries.o5m

USER root
# Install dos2unix to fix problems with building docker containers on windows.
RUN apt-get install -y dos2unix
# Filter administrative boundaries
USER nominatim
ARG BUILD_THREADS=16
ARG IMPORT_ADMINISTRATIVE=false
COPY scripts/filter_administrative.sh \
      /srv/nominatim/scripts/filter_administrative_pre.sh
USER root
RUN chmod a+rw /srv/nominatim/scripts/filter_administrative_pre.sh
RUN dos2unix -n /srv/nominatim/scripts/filter_administrative_pre.sh /srv/nominatim/scripts/filter_administrative.sh
USER nominatim
RUN /srv/nominatim/scripts/filter_administrative.sh

# Add postgresql users
USER root
RUN service postgresql start && \
    sudo -u postgres createuser -s nominatim && \
    sudo -u postgres createuser www-data && \
    service postgresql stop

# Tune postgresql configuration for import
USER root
ARG BUILD_MEMORY=32GB
ENV PGCONFIG_URL https://api.pgconfig.org/v1/tuning/get-config
RUN IMPORT_CONFIG_URL="${PGCONFIG_URL}? \
      format=alter_system& \
      pg_version=${PGSQL_VERSION}& \
      total_ram=${BUILD_MEMORY}& \
      max_connections=$((8 * ${BUILD_THREADS} + 32))& \
      environment_name=DW& \
      include_pgbadger=false" && \
    IMPORT_CONFIG_URL=${IMPORT_CONFIG_URL// /} && \
    service postgresql start && \
    ( curl -sSL "${IMPORT_CONFIG_URL}"; \
      echo $'ALTER SYSTEM SET fsync TO \'off\';\n'; \
      echo $'ALTER SYSTEM SET full_page_writes TO \'off\';\n'; \
      echo $'ALTER SYSTEM SET logging_collector TO \'off\';\n'; \
    ) | sudo -u postgres psql -e && \
    service postgresql stop

# Initial import
USER root
ARG OSM2PGSQL_CACHE=24000

# Make sure nominatim has proper dependencies installed.


RUN service postgresql start && \
    sudo -u nominatim ${USERHOME}/Nominatim/build/utils/setup.php \
      --osm-file /srv/nominatim/src/data.osm.pbf \
      --all \
      --threads ${BUILD_THREADS} \
      --osm2pgsql-cache ${OSM2PGSQL_CACHE} && \
    service postgresql stop

# Use safe postgresql configuration
USER root
ARG RUNTIME_THREADS=2
ARG RUNTIME_MEMORY=8GB
RUN IMPORT_CONFIG_URL="${PGCONFIG_URL}? \
      format=alter_system& \
      pg_version=${PGSQL_VERSION}& \
      total_ram=${RUNTIME_MEMORY}& \
      max_connections=$((8 * ${RUNTIME_THREADS} + 32))& \
      environment_name=WEB& \
      include_pgbadger=true" && \
    IMPORT_CONFIG_URL=${IMPORT_CONFIG_URL// /} && \
    service postgresql start && \
    ( curl -sSL "${IMPORT_CONFIG_URL}"; \
      echo $'ALTER SYSTEM SET fsync TO \'on\';\n'; \
      echo $'ALTER SYSTEM SET full_page_writes TO \'on\';\n'; \
      echo $'ALTER SYSTEM SET logging_collector TO \'on\';\n'; \
    ) | sudo -u postgres psql -e && \
    service postgresql stop

# Configure Apache
USER root
COPY nominatim.conf /etc/apache2/conf-available/nominatim.conf
RUN a2enconf nominatim

# Clean up
USER root
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Expose ports
EXPOSE 8080

# Init scripts
USER root
ENV KILL_PROCESS_TIMEOUT=300
ENV KILL_ALL_PROCESSES_TIMEOUT=300
RUN mkdir -p /etc/my_init.d
COPY scripts/start_postgresql.sh /etc/my_init.d/00-postgresql_pre.sh
RUN dos2unix -n /etc/my_init.d/00-postgresql_pre.sh /etc/my_init.d/00-postgresql.sh
RUN rm /etc/my_init.d/00-postgresql_pre.sh
RUN chmod +x /etc/my_init.d/00-postgresql.sh
COPY scripts/start_apache2.sh /etc/my_init.d/00-apache2_pre.sh
RUN dos2unix -n /etc/my_init.d/00-apache2_pre.sh /etc/my_init.d/00-apache2.sh
RUN rm /etc/my_init.d/00-apache2_pre.sh
RUN chmod +x /etc/my_init.d/00-apache2.sh
CMD ["/sbin/my_init"]
