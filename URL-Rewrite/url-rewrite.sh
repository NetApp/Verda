#!/bin/sh

# This script currently swaps all container images between $region1 and $region2 when invoked.
# Order does not matter, if $region1 is active at the time of invocation, then $region2 will be the
# new region. If $region2 is active, then $region1 becomes the new active region.
#
# At the time of writing, only "deployment" swapping is supported, however this script is built in
# a way to support other Kubernetes objects.

NOUNS="deployment"

swap_regions_per_container() {
    region1=$1
    region2=$2
    noun=$3
    object=$4
    c=$5

    # Get the image and image region
    full_image=$(kubectl get ${noun} ${object} -o json | jq -r --arg con "$c" '.spec.template.spec.containers[] | select(.name == $con) | .image')
    region=$(echo ${full_image} | cut -d "/" -f -1)
    base_image=$(echo ${full_image} | cut -d "/" -f 2-)

    # Swap the region
    if [ ${region} = ${region1} ] ; then
        new_region=${region2}
    else
        new_region=${region1}
    fi

    # Rebuild the image string
    new_full_image=$(echo ${new_region}/${base_image})

    # Update the image
    kubectl set image ${noun}/${object} ${c}=${new_full_image}
}

swap_regions_per_object() {
    region1=$1
    region2=$2
    noun=$3
    object=$4

    # Loop through the containers within an object
    containerNames=$(kubectl get ${noun} ${object} -o json | jq -r '.spec.template.spec.containers[].name')
    for c in ${containerNames}; do
        swap_regions_per_container "${region1}" "${region2}" "${noun}" "${object}" "${c}"
    done
}

swap_regions_per_noun() {
    region1=$1
    region2=$2
    noun=$3

    # Gather the non-"astra-hook-deployment" objects based on $noun
    if [ "${noun}" = "deployment" ]; then
        objects=$(kubectl get deployments -o json | jq -r '.items[].metadata | select(.name != "astra-hook-deployment") | .name')
    fi

    # Loop through non-"astra-hook-deployment" deployments
    for object in ${objects}; do
        swap_regions_per_object "${region1}" "${region2}" "${noun}" "${object}"
    done
}

swap_regions() {
    region1=$1
    region2=$2

    # Loop through all NOUNS
    for noun in ${NOUNS}; do
        swap_regions_per_noun "${region1}" "${region2}" "${noun}"
    done
}


#
# main
#

# check arg
region1=$1
region2=$2
if [ -z "${region1}" ] || [ -z "${region2}" ]; then
    echo "Usage: $0 <region1> <region2>"
    exit ${eusage}
fi

swap_regions "${region1}" "${region2}"
