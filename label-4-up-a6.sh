#!/bin/bash

# set -o xtrace
set -e
set -o pipefail

SELF=$(basename $0)
TMP_DIR=$(mktemp -d /tmp/${SELF}.XXXXXXXXXX)

error() {
    echo "error: $*" >&2
    exit
}

pdfOrientation() {
    pdfinfo ${1} \
        | awk '
/Page size/ {
    width=$3
    height=$5
    if(width > height) {
        print "landscape"
    } else {
        print "portrait"
    }
    exit(0)
};
/END/ {
    exit(1)
}'
}

createEmptyA6Page() {
    convert xc:none -page A6 ${1}
}

echo ${TMP_DIR}

PAGE_NUMBER=1

for IN_FILENAME in "$@"; do
    OUT_FILENAME=$(printf "${TMP_DIR}/%.8d.pdf" ${PAGE_NUMBER})
    if [ "${IN_FILENAME}" = "-" ]; then
        createEmptyA6Page ${OUT_FILENAME}
    else
        pdfOrientation ${IN_FILENAME}
        ORIENTATION=$(pdfOrientation ${IN_FILENAME}) || error "${IN_FILENAME}: cannot determine orientation of pdf"
        if [ "${ORIENTATION}" = "portrait" ]; then
            pdfjam --paper a6paper --scale 0.9 --outfile ${OUT_FILENAME} ${IN_FILENAME} 1
        else
            pdfjam --angle 90 --paper a6paper --scale 0.9 --outfile ${OUT_FILENAME} ${IN_FILENAME} 1
        fi
    fi
    echo "${IN_FILENAME} ${OUT_FILENAME}"
    let "PAGE_NUMBER++"
done

pdfjam --nup 2x2 --outfile ${TMP_DIR}/output.pdf ${TMP_DIR}/*.pdf

xdg-open ${TMP_DIR}/output.pdf

sleep 3

read -n1 -p "Clean up temporary files in ${TMP_DIR} (y/n)? " CHOICE
echo

case "${CHOICE}" in
    n|N)
        echo "${TMP_DIR} left dirty"
        ;;
    *)
        rm -rf ${TMP_DIR}
        echo "${TMP_DIR} removed"
        ;;
esac
