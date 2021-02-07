#!/bin/bash

# set -o xtrace
set -e
set -o pipefail

SELF=$(basename $0)
TMP_DIR=$(mktemp -d /tmp/${SELF}.XXXXXXXXXX)
TMP2_DIR=${TMP_DIR}/tmp

error() {
    echo "error: $*" >&2
    exit
}

pdfPageSize() {
    pdfinfo "${1}" \
        | awk -F '(: +)|( +x +)|([(])|([)])|( +pts +)' '
/Page size/ {
    width=$2
    height=$3
    pageSize=$5
    if(length(pageSize)) {
        print pageSize
    } else {
        print "unknown"
    }
    exit(0)
};
/END/ {
    exit(1)
}'
}

pdfOrientation() {
    pdfinfo "${1}" \
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

pdfJam() {
    pdfjam --quiet "$@"
}

PAGE_NUMBER=1

for IN_FILENAME in "$@"; do
    NUMBER=$(printf "%.8d" ${PAGE_NUMBER})
    echo -n "${NUMBER}: "
    OUT_FILENAME="${TMP_DIR}/${NUMBER}.pdf"
    if [ "${IN_FILENAME}" = "-" ]; then
        echo -n "empty page"
        createEmptyA6Page ${OUT_FILENAME}
    else
        echo -n "${IN_FILENAME}"
        PAGE_SIZE=$(pdfPageSize "${IN_FILENAME}") || error "${IN_FILENAME}: cannot determine page size of pdf"
        if [ "${PAGE_SIZE}" = "A4" ]; then
            echo -n ", trim upper right A6 from A4"
            mkdir -p ${TMP2_DIR}
            NEW_IN_FILENAME=${TMP2_DIR}/$(basename "${OUT_FILENAME}")
            pdfJam --paper a6paper --angle 90 --trim '148.5mm 105mm 0mm 0mm' --clip true --outfile ${NEW_IN_FILENAME} "${IN_FILENAME}" 1
            IN_FILENAME=${NEW_IN_FILENAME}
        fi
        ORIENTATION=$(pdfOrientation "${IN_FILENAME}") || error "${IN_FILENAME}: cannot determine orientation of pdf"
        if [ "${ORIENTATION}" = "portrait" ]; then
            pdfJam --paper a6paper --scale 0.9 --outfile ${OUT_FILENAME} "${IN_FILENAME}" 1
        else
            echo -n ", rotate 90°"
            pdfJam --paper a6paper --scale 0.9 --angle 90 --outfile ${OUT_FILENAME} "${IN_FILENAME}" 1
        fi
        echo -n ", scale to 90%"
    fi
    echo "."
    let "PAGE_NUMBER++"
done

pdfJam --nup 2x2 --outfile ${TMP_DIR}/output.pdf ${TMP_DIR}/*.pdf

xdg-open ${TMP_DIR}/output.pdf 2>/dev/null

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
