#!/bin/bash

# Important: This script is run under QEMU

set -e

# TODO: Use our own cache
CACHING_SERVICE="http://kernelci1.eastus.cloudapp.azure.com:8888/cache?uri="

# Verify if CACHING_SERVICE is reachable by curl, if not, unset it
if [ ! -z ${CACHING_SERVICE} ]; then
  # disable set -e
  set +e
  curl -s --head --request GET ${CACHING_SERVICE}
  # if exit code is not 0, unset CACHING_SERVICE
  if [ $? -ne 0 ]; then
	echo "CACHING_SERVICE is not reachable, unset it"
	unset CACHING_SERVICE
  fi
  set -e
fi

########################################################################
# Get fluster                                                          #
########################################################################
get_json_obj_field() {
	local json_obj=${1}
	local field=${2}

	echo "${json_obj}" | jq ".${field}" | tr -d '"'
}

extract_vector_from_archive() {
	local archive_filename
	archive_filename=$(readlink -e "${1}")

	local vector_filename=${2}

	case "${archive_filename}" in
	*.tar.gz | *.tgz | *.tar.bz2 | *.tbz2)
		tar -xf "${archive_filename}"
		;;
	*.zip)
		unzip -o "${archive_filename}" "${vector_filename}"
		;;
	*)
		return
		;;
	esac

	rm "${archive_filename}"
}

download_fluster_testsuite() {
	json_file=$(readlink -e "${1}")

	[ -z "${json_file}" ] && {
		echo "No JSON test suite file provided"
		exit 1
	}

	if [ ! -f "${json_file}" ]; then
		echo "${json_file} file not found!"
		exit 1
	fi

	suite_name=$(jq '.name' "${json_file}" | tr -d '"')

	# Create and enter suite directory
	mkdir --parents ./resources/"${suite_name}" && pushd "$_" || exit

	vector_count=$(jq '.test_vectors | length' "${json_file}")

	for i in $(seq 0 $((vector_count - 1))); do
		vector_json_obj=$(jq -c '.test_vectors['"${i}"']' "${json_file}")

		# Parse JSON to get vector information
		vector_name=$(get_json_obj_field "${vector_json_obj}" 'name')
		vector_url=$(get_json_obj_field "${vector_json_obj}" 'source')
		vector_md5=$(get_json_obj_field "${vector_json_obj}" 'source_checksum')
		vector_filename=$(get_json_obj_field "${vector_json_obj}" 'input_file')

		vector_archive=$(basename "${vector_url}")

		# Create and enter vector directory
		mkdir --parents "${vector_name}" && pushd "$_" || exit

		# Download the test vector
		if [ -z ${CACHING_SERVICE} ]; then
		  wget --no-verbose --inet4-only --no-clobber --tries 5 "${vector_url}" || exit
		else
		  echo "${CACHING_SERVICE}${vector_url}"
		  wget --no-verbose --inet4-only --no-clobber --tries 5 "${CACHING_SERVICE}${vector_url}" -O  "${vector_archive}" || exit
		fi

		# Verify checksum
		if [ "${vector_md5}" != "$(md5sum "${vector_archive}" | cut -d' ' -f1)" ]; then
			echo "MD5 mismatch, exiting"
			exit 1
		else
			# Unpack if necessary
			extract_vector_from_archive "${vector_archive}" "${vector_filename}"
		fi

		popd || exit

	done

	popd || exit

}

# TODO: Switch to upstream
#FLUSTER_URL=https://github.com/fluendo/fluster.git
FLUSTER_URL=https://github.com/Gnurou/fluster.git

mkdir -p /opt/fluster && cd /opt/fluster

git clone $FLUSTER_URL .
git checkout cros-codecs

# Temporarily limit to h264
#download_fluster_testsuite ./test_suites/av1/AV1-TEST-VECTORS.json
#download_fluster_testsuite ./test_suites/h264/JVT-AVC_V1.json
#download_fluster_testsuite ./test_suites/h265/JCT-VC-HEVC-V1.json
#download_fluster_testsuite ./test_suites/vp8/VP8-TEST-VECTORS.json
#download_fluster_testsuite ./test_suites/vp9/VP9-TEST-VECTORS.json

########################################################################
# Cleanup: remove files and packages we don't want in the images       #
########################################################################
rm -rf /var/tests

apt-get remove --purge -y ${BUILD_DEPS}
apt-get autoremove --purge -y
apt-get clean
