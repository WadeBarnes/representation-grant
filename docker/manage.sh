#!/bin/bash
export MSYS_NO_PATHCONV=1
set -e

S2I_EXE=s2i
if [ -z $(type -P "$S2I_EXE") ]; then
  echo -e "The ${S2I_EXE} executable is needed and not on your path."
  echo -e "It can be downloaded from here: https://github.com/openshift/source-to-image"
  echo -e "Make sure you place it in a directory on your path."
  exit 1
fi

SCRIPT_HOME="$( cd "$( dirname "$0" )" && pwd )"
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME-fpo}"

# =================================================================================================================
# Usage:
# -----------------------------------------------------------------------------------------------------------------
usage() {
  cat <<-EOF

  Usage: $0 {start|stop|build|rm}

  Options:

  build - Build the docker images for the project.
          You need to do this first, since the builds require
          a combination of Docker and S2I builds.

  start - Creates the application containers from the built images
          and starts the services based on the docker-compose.yml file.

          You can pass in a list of containers to start.  
          By default all containers will be started.
          
          The API_URL used by web can also be redirected.

          Examples:
          $0 start
          $0 start web
          $0 start web API_URL=http://docker.for.win.localhost:56325/api/v1

  stop - Stops the services.  This is a non-destructive process.  The containers
         are not deleted so they will be reused the next time you run start.

  rm - Removes any existing application containers.
EOF
exit 1
}
# -----------------------------------------------------------------------------------------------------------------
# Default Settings:
# -----------------------------------------------------------------------------------------------------------------
DEFAULT_CONTAINERS="db api schema-spy web pdf"
# -----------------------------------------------------------------------------------------------------------------
# Functions:
# -----------------------------------------------------------------------------------------------------------------
build-web() {
  #
  # web
  #
  # The nginx-runtime image is used for the final runtime image.
  # The angular-app image is used to build the artifacts for the angular distribution.
  # The angular-on-nginx image is copy of the nginx-runtime image complete with a copy of the build artifacts.
  #
  echo -e "\n\n===================================================================================================="
  echo -e "Building the nginx-runtime image using Docker ..."
  echo -e "----------------------------------------------------------------------------------------------------"
  docker build \
    -t 'nginx-runtime' \
    -f '../web/openshift/templates/nginx-runtime/Dockerfile' '../web/openshift/templates/nginx-runtime/'
  echo -e "===================================================================================================="
  
  echo -e "\n\n===================================================================================================="
  echo -e "Building the angular-app image using s2i ..."
  echo -e "----------------------------------------------------------------------------------------------------"
  ${S2I_EXE} build \
    '../web' \
    'centos/nodejs-6-centos7:6' \
    'angular-app'
  echo -e "===================================================================================================="

  echo -e "\n\n===================================================================================================="
  echo -e "Building the angular-on-nginx image using Docker ..."
  echo -e "----------------------------------------------------------------------------------------------------"
  docker build \
    -t 'angular-on-nginx' \
    -f '../web/openshift/templates/angular-on-nginx/Dockerfile' '../web/openshift/templates/angular-on-nginx/'
  echo -e "===================================================================================================="
}

build-db() {
  #
  # db
  #
  # Nothing to build here ...
  echo
}

build-schema-spy() {
  #
  # schema-spy
  #
  echo -e "\nBuilding schema-spy image ..."
  docker build \
    https://github.com/bcgov/SchemaSpy.git \
    -t 'schema-spy'
}

build-api() {
  #
  # api
  #
  echo -e "\nBuilding django image ..."
  ${S2I_EXE} build \
    '../api' \
    'centos/python-36-centos7' \
    'django'
}

build-pdf() {
  #
  # pdf
  #
  echo -e "\nGetting pdf image ..."
  docker pull aquavitae/weasyprint
  docker tag aquavitae/weasyprint pdf
}

buildImages() {
  build-web
  build-db
  build-schema-spy
  build-api
  build-pdf
}

build() {
  # Build all containers in the docker-compose file
  echo -e "\nBuilding containers ..."
  echo docker-compose build $@
  docker-compose build $@
}

configureEnvironment () {
  for arg in $@; do
    case "$arg" in
      *=*)
        export ${arg}
        ;;  
    esac
  done
  
  # db
  export POSTGRESQL_DATABASE="FAMILY_PROTECTION_ORDER"
  export POSTGRESQL_USER="DB_USER"
  export POSTGRESQL_PASSWORD="DB_PASSWORD"

  # schema-spy
  export DATABASE_SERVICE_NAME="db"
  export POSTGRESQL_DATABASE=${POSTGRESQL_DATABASE}
  export POSTGRESQL_USER=${POSTGRESQL_USER}
  export POSTGRESQL_PASSWORD=${POSTGRESQL_PASSWORD}

  # api
  export API_HTTP_PORT=${API_HTTP_PORT-8081}
  export PDF_SERVICE_URL=${PDF_SERVICE_URL-http://pdf:5001}
  export OVERRIDE_USER_ID=${OVERRIDE_USER_ID-}
  export DATABASE_SERVICE_NAME="db"
  export DATABASE_ENGINE="postgresql"
  export DATABASE_NAME=${POSTGRESQL_DATABASE}
  export DATABASE_USER=${POSTGRESQL_USER}
  export DATABASE_PASSWORD=${POSTGRESQL_PASSWORD}
  export DJANGO_SECRET_KEY=wpn1GZrouOryH2FshRrpVHcEhMfMLtmTWMC2K5Vhx8MAi74H5y
  export DJANGO_DEBUG=True

  # web
  export WEB_HTTP_PORT=${WEB_HTTP_PORT-8080}
  export API_URL=${API_URL-http://api:8080/api/v1/}
  export IpFilterRules='#allow all; deny all;'
  export RealIpFrom='127.0.0.0/16'
}

getStartupParams() {
  CONTAINERS=""
  ARGS="--force-recreate"

  for arg in $@; do
    case "$arg" in
      *=*)
        # Skip it
        ;;  
     -*)
        ARGS+=" $arg";;
      *)
        CONTAINERS+=" $arg";;
    esac
  done

  if [ -z "$CONTAINERS" ]; then
    CONTAINERS="$DEFAULT_CONTAINERS"
  fi

  echo ${ARGS} ${CONTAINERS}
}

deleteVolumes() {
  _projectName=${COMPOSE_PROJECT_NAME:-docker}

  echo "Stopping and removing any running containers ..."
  docker-compose rm -svf >/dev/null

  _pattern="^${_projectName}_\|^docker_"
  _volumes=$(docker volume ls -q | grep ${_pattern})

  if [ ! -z "${_volumes}" ]; then
    echo "Removing project volumes ..."
    echo ${_volumes} |  xargs docker volume rm
  else
    echo "No project volumes exist."
  fi
}

toLower() {
  echo $(echo ${@} | tr '[:upper:]' '[:lower:]')
}

# =================================================================================================================

pushd ${SCRIPT_HOME} >/dev/null
COMMAND=$(toLower ${1})
shift

case "$COMMAND" in
  start)
    _startupParams=$(getStartupParams $@)
    configureEnvironment $@
    docker-compose up ${_startupParams}
    ;;
  stop)
    configureEnvironment
    docker-compose stop
    ;;
  rm)
    configureEnvironment
    deleteVolumes
    ;;
  build)
    case "$@" in
      api)
        build-api
        ;;
      web)
        build-web
        ;;
      fpo-solr)
        build-solr
        ;;
      pdf)
        build-pdf
        ;;
      *)
       buildImages
    esac
    ;;
  *)
    usage
esac

popd >/dev/null
