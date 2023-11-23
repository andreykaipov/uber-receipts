# uber-receipts

Download your Uber trip receipts in bulk easily.

## instructions

Before running this script, you'll need login to https://riders.uber.com
and get the respective cookies from your browser, setting them as the
following environment variables:

```sh
export cookie_sid=...
export cookie_csid=...
```

Now we can use it to download our trip history and receipts:

- By default, the script will iterate over all our trips in the current
  year. To change it, the `from` and `to` timestamps must be provided in
  milliseconds since epoch.

- By default, the script will only list the trips in CSV format. To also
  download the corresponding receipts, set `download=1`. They'll be saved
  to `receipts/` in the current directory by default.

## usage and examples

```
Usage:
    [from=...] [to=...] [download=1] [outdir=receipts] ./uber-receipts.sh

Examples:
    # view history from 2021
    from=$(date -d2021-01-01 +%s%3N) to=$(date -d2021-12-31 +%s%3N) ./uber-receipts.sh

    # download receipts for the current year
    download=1 ./uber-receipts.sh
```
