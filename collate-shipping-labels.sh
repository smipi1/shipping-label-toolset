#!/bin/bash

# set -o xtrace
set -e
set -o pipefail

SELF=$(basename $0)
TMP_DIR=$(mktemp -d /tmp/${SELF}.XXXXXXXXXX)
EU_DIR=${TMP_DIR}/europe
INTL_DIR=${TMP_DIR}/international
TMP2_DIR=${TMP_DIR}/tmp

error() {
    echo
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

documentType() {
    if pdfgrep -q -P 'EXPRESS WORLDWIDE\n.*ECX' ${1}; then
        echo "dhl-label-ecx"
    elif pdfgrep -q -P 'EXPRESS WORLDWIDE\n.*WPX' ${1}; then
        echo "dhl-label-wpx"
    elif pdfgrep -q 'Commercial Invoice.*Carrier: *DHL' ${1}; then
        echo "dhl-invoice"
    elif pdfgrep -q -P '3SGHUB' ${1}; then
        echo "postnl-label"
    fi
}

isShippingLabel() {
    pdfgrep -q -P '(EXPRESS WORLDWIDE\n.*(ECX|WPX)|3SGHUB)' ${1}
}

isInternational() {
    pdfgrep -q -P 'EXPRESS WORLDWIDE\n.*WPX' ${1}
}

isCommercialInvoiceFor() {
    local IN_FILENAME=${1};shift
    local ORDER_NUMBER=${1};shift
    pdfgrep -q 'Commercial Invoice.*Shipment Reference: +'${ORDER_NUMBER}'.*Carrier: *DHL' ${IN_FILENAME}
}

dhlReference() {
    local LABEL_FILENAME=${1};shift
    pdfgrep '.*' ${LABEL_FILENAME} | awk '/^Ref: /{print $2}'
}

dhlCommercialInvoice() {
    local ORDER_NUMBER=${1};shift
    local IN_FILENAME;
    for IN_FILENAME in "${ARGS[@]}"; do
        if [ "${IN_FILENAME}" = "-" ]; then
            continue
        elif isCommercialInvoiceFor "${IN_FILENAME}" ${ORDER_NUMBER}; then
            echo "${IN_FILENAME}"
            return 0
        fi
    done
    return 1
}

PAGE_NUMBER=1

ARGS=( "$@" )

for ARG in "${ARGS[@]}"; do
    IFS=':' read -r IN_FILENAME IN_PAGE <<< "${ARG}"
    if [ -n "${IN_PAGE}" ]; then
        mkdir -p ${TMP2_DIR}
        NEW_IN_FILENAME=${TMP2_DIR}/page_subset.pdf
        pdftk ${IN_FILENAME} cat ${IN_PAGE} output - > ${NEW_IN_FILENAME} || error "${IN_FILENAME}: cannot extract page ${IN_PAGE}"
        IN_FILENAME=${NEW_IN_FILENAME}
    fi
    NUMBER=$(printf "%.8d" ${PAGE_NUMBER})
    echo -n "${NUMBER}: "
    OUT_FILENAME="${EU_DIR}/${NUMBER}.pdf"
    if [ "${IN_FILENAME}" = "-" ]; then
        mkdir -p ${EU_DIR}
        echo -n "europe, empty page"
        createEmptyA6Page ${OUT_FILENAME}
    elif isShippingLabel ${IN_FILENAME}; then
        echo -n "${IN_FILENAME}: "
        if isInternational ${IN_FILENAME}; then
            mkdir -p ${INTL_DIR}
            OUT_FILENAME="${INTL_DIR}/${NUMBER}.pdf"
            echo -n "international"
            ORDER_NUMBER=$(dhlReference ${IN_FILENAME}) || error "${IN_FILENAME}: cannot determine order number"
            INVOICE=$(dhlCommercialInvoice ${ORDER_NUMBER}) || error "${IN_FILENAME}: cannot find commercial invoice for order number ${ORDER_NUMBER} in input files"
            echo -n ", ${INVOICE}: commercial invoice"
            mkdir -p ${TMP2_DIR}
            NEW_IN_FILENAME=${TMP2_DIR}/$(basename "${OUT_FILENAME}")
            pdfJam --paper a6paper --scale 0.9 --outfile ${NEW_IN_FILENAME}.label.pdf "${IN_FILENAME}" 1
            pdfJam --paper a4paper --nup 2x2 --outfile ${NEW_IN_FILENAME}.labels.pdf ${NEW_IN_FILENAME}.label.pdf ${NEW_IN_FILENAME}.label.pdf
            pdfJam --paper a4paper --outfile ${OUT_FILENAME} ${NEW_IN_FILENAME}.labels.pdf ${INVOICE} ${INVOICE}
        else
            mkdir -p ${EU_DIR}
            echo -n "europe"
            PAGE_SIZE=$(pdfPageSize "${IN_FILENAME}") || (echo; error "${IN_FILENAME}: cannot determine page size of pdf")
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
    else
        echo -n "${IN_FILENAME}: skipped"
    fi
    echo "."
    let "PAGE_NUMBER++"
done

if compgen -G "${EU_DIR}/*.pdf" >/dev/null; then
    OUTFILE_EU=${EU_DIR}/europe-print-on-2x2-A6-label-sheets.pdf
    echo "European labels: ${OUTFILE_EU}"
    pdfJam --nup 2x2 --outfile ${OUTFILE_EU} ${EU_DIR}/*.pdf
    xdg-open ${OUTFILE_EU} 2>/dev/null
fi

if compgen -G "${INTL_DIR}/*.pdf" >/dev/null; then
    OUTFILE_INTL=${INTL_DIR}/international-print-on-A4-sheets.pdf
    echo "International waybills and invoices: ${OUTFILE_INTL}"
    pdfJam --outfile ${OUTFILE_INTL} ${INTL_DIR}/*.pdf
    xdg-open ${OUTFILE_INTL} 2>/dev/null
fi

sleep 3

read -n1 -p "Clean up temporary files in ${TMP_DIR} (y/n)? " CHOICE
echo

case "${CHOICE}" in
    n|N)
        echo "${TMP_DIR} left dirty";
        ;;
    *)
        rm -rf ${TMP_DIR};
        echo "${TMP_DIR} removed";
        ;;
esac

exit 0
