#!/bin/bash
# shellcheck disable=SC2016

query_get_trip='
  query GetTrip($tripUUID: String!) {
    getTrip(tripUUID: $tripUUID) {
      trip {
        beginTripTime
        cityID
        countryID
        disableCanceling
        disableRating
        driver
        dropoffTime
        fare
        isRidepoolTrip
        isScheduledRide
        isSurgeTrip
        isUberReserve
        jobUUID
        marketplace
        paymentProfileUUID
        status
        uuid
        vehicleDisplayName
        vehicleViewID
        waypoints
        __typename
      }
      mapURL
      polandTaxiLicense
      rating
      receipt {
        carYear
        distance
        distanceLabel
        duration
        vehicleType
        __typename
      }
      __typename
    }
  }
'

query_get_trips='
  query GetTrips($cursor: String, $fromTime: Float, $toTime: Float) {
    getTrips(cursor: $cursor, fromTime: $fromTime, toTime: $toTime) {
      count
      pagingResult {
        hasMore
        nextCursor
        __typename
      }
      trips {
        ...TripFragment
        __typename
      }
      __typename
    }
  }

  fragment TripFragment on Trip {
    fare
    beginTripTime
    dropoffTime
    status
    uuid
    __typename
  }
'

uber() {
        api=https://riders.uber.com
        path=$1
        shift
        command curl -s --compressed "$api$path" \
                -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/119.0' \
                -H 'Accept: */*' \
                -H 'Accept-Language: en-US,en;q=0.5' \
                -H 'Accept-Encoding: gzip, deflate, br' \
                -H 'content-type: application/json' \
                -H 'x-csrf-token: x' \
                -H 'Origin: https://riders.uber.com' \
                -H "Cookie: sid=${cookie_sid?}" \
                -H "Cookie: csid=${cookie_csid?}" \
                -H "Cookie: jwt-session=${cookie_jwt?}" \
                -H 'Sec-Fetch-Dest: empty' \
                -H 'Sec-Fetch-Mode: cors' \
                -H 'Sec-Fetch-Site: same-origin' \
                -H 'TE: trailers' \
                "$@"
}

get_trips() {
        year=$(date +%Y)
        : "${cursor=""}"
        : "${from=$(date -d"$year-01-01 00:00:00" +%s%3N)}"
        : "${to=$(date +%s%3N)}"
        body=$(
                jq <<<"$query_get_trips" -Rs \
                        --arg cursor "$cursor" \
                        --arg from "$from" \
                        --arg to "$to" \
                        '{
                            operationName:"GetTrips",
                            variables:{
                              cursor:$cursor,
                              fromTime:($from|tonumber),
                              toTime:($to|tonumber)
                            },
                            query:.
                         }'
        )
        uber /graphql --data-raw "$body"
}

get_trip() {
        : "${uuid=""}"
        body=$(
                jq <<<"$query_get_trip" -Rs \
                        --arg uuid "$uuid" \
                        '{
                            operationName:"GetTrip",
                            variables:{
                              tripUUID:$uuid
                            },
                            query:.
                         }'
        )
        uber /graphql --data-raw "$body"
}

make_csv() {
        while :; do
                trips=$(get_trips)
                uuids=$(jq <<<"$trips" -rc .data.getTrips.trips[].uuid)

                # some fields like fare don't seem to be always present in the
                # getTrips query, so we have to call getTrip for each
                for uuid in $uuids; do
                        trip=$(get_trip)
                        status=$(jq <<<"$trip" -r .data.getTrip.trip.status)
                        fare=$(jq <<<"$trip" -r .data.getTrip.trip.fare)
                        driver=$(jq <<<"$trip" -r .data.getTrip.trip.driver)
                        fromaddr=$(jq <<<"$trip" -r .data.getTrip.trip.waypoints[0])
                        toaddr=$(jq <<<"$trip" -r .data.getTrip.trip.waypoints[1])
                        begin=$(jq <<<"$trip" -r .data.getTrip.trip.beginTripTime)
                        dropoff=$(jq <<<"$trip" -r .data.getTrip.trip.dropoffTime)

                        # better dates, using @csv with jq would be too annoying
                        begin=$(TZ=UTC date -d "$begin" +'%Y-%m-%dT%H-%M-%SZ')
                        dropoff=$(TZ=UTC date -d "$dropoff" +'%Y-%m-%dT%H-%M-%SZ')
                        printf '"%s","%s","%s","%s","%s","%s","%s","%s"\n' "$uuid" "$status" "$fare" "$driver" "$fromaddr" "$begin" "$toaddr" "$dropoff"

                        if [ -n "$download" ]; then
                                download_receipt "$uuid"
                        fi
                done

                has_more=$(jq <<<"$trips" -r .data.getTrips.pagingResult.hasMore)
                cursor=$(jq <<<"$trips" -r .data.getTrips.pagingResult.nextCursor)
                if [[ $has_more == false ]]; then break; fi
                sleep 5
        done
}

download_receipt() {
        : "${uuid=""}"
        : "${outdir=receipts}"
        mkdir -p "$outdir"
        fare=$(jq <<<"$trip" -r .data.getTrip.trip.fare)
        uber "/trips/$uuid/receipt?contentType=PDF" -Lo "$outdir/$begin $fare $uuid.pdf"
}

usage() {
        cat <<EOF
Instructions:

Before running this script, you'll need login to https://riders.uber.com
and get the respective cookies from your browser, setting them as the
following environment variables:

export cookie_sid=...
export cookie_csid=...
export cookie_jwt=...

Now we can use it to download our trip history and receipts:

- By default, the script will iterate over all our trips in the current
  year. To change it, the 'from' and 'to' timestamps must be provided in
  milliseconds since epoch.

- By default, the script will only list the trips in CSV format. To also
  download the corresponding receipts, set 'download=1'. They'll be saved
  to receipts/ in the current directory by default.

Usage:
    [from=...] [to=...] [download=1] [outdir=receipts] $0

Examples:
    # view history from 2021
    from=\$(date -d2021-01-01 +%s%3N) to=\$(date -d2021-12-31 +%s%3N) $0

    # download receipts for the current year
    download=1 $0
EOF
        exit 1
}

main() {
        if [[ -z $cookie_sid || -z $cookie_csid || -z $cookie_jwt ]]; then usage; fi
        make_csv
}

main "$@"
