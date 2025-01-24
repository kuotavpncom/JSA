#!/bin/bash

stdin=$(</dev/stdin)

array=()
for i in {a..z} {A..Z} {0..9}; do
    array[$RANDOM]=$i
done
random_str=$(printf %s ${array[@]::23})

## fetching js files with subjs tool
printf 'Fetching js files with subjs tool..\n'
printf $stdin | subjs | tee tmp/subjs${random_str}.txt | httpx -sc -mc 200 -silent >/dev/null


## lauching wayback with a "js only" mode to reduce execution time
printf 'Launching Gau with wayback..\n'
printf $stdin | xargs -I{} echo "{}/*&filter=mimetype:application/javascript&somevar=" | gau --providers wayback | tee tmp/gau${random_str}.txt | httpx -sc -mc 200 -silent >/dev/null   ##gau
printf $stdin | xargs -I{} echo "{}/*&filter=mimetype:text/javascript&somevar=" | gau --providers wayback | tee -a tmp/gau${random_str}.txt | httpx -sc -mc 200 -silent >/dev/null   ##gau


## if js file parsed from wayback didn't return 200 live, we are generating a URL to see a file's content on wayback's server;
## it's useless for endpoints discovery but there is a point to search for credentials in the old content; that's what we'll do
## only wayback as of now
printf "Fetching URLs for 404 js files from wayback..\n"
cat tmp/gau${random_str}.txt | cut -d '?' -f1 | cut -d '#' -f1 | sort -u | xargs -I{} sh -c automation/404_js_wayback.sh {} | tee -a tmp/creds_search${random_str}.txt | httpx -sc -mc 200 -silent >/dev/null


## Classic crawling. It could give different results than subjs tool
resolved_url=$(curl -Ls -o /dev/null -w '%{url_effective}' "$stdin")
echo "Resolved URL: $resolved_url"
printf 'Now crawling web pages..\n'
echo $resolved_url | hakrawler -u -subs -insecure -d 2 | grep '\.js' | tee tmp/spider${random_str}.txt | httpx -sc -mc 200 -silent >/dev/null
   
   ##just crawling web pages


## Searching for URLs in github, - that could give some unique results, too
## python one-liner - for clear domain matching


## sorting out all the results
##that's for creds_check

cat tmp/subjs${random_str}.txt tmp/gau${random_str}.txt tmp/spider${random_str}.txt | cut -d '?' -f1 | cut -d '#' -f1 | grep -E '\.js(?:onp?)?$' | sort -u | tee tmp/all_js_files${random_str}.txt | httpx -sc -mc 200 -silent >/dev/null 

## save all endpoints to the file for future processing

## extracting js files from js files
printf "Printing deep-level js files..\n"
cat tmp/all_js_files${random_str}.txt | parallel --gnu --pipe -j 15 "python3 automation/js_files_extraction.py | tee -a tmp/all_js_files${random_str}.txt | httpx -sc -mc 200 -silent"

printf "Searching for endpoints..\n"
cat tmp/all_js_files${random_str}.txt | parallel --gnu --pipe -j 15 "python3 automation/endpoints_extraction.py | tee -a tmp/all_endpoints${random_str}.txt | httpx -sc -mc 200 -silent"
cat tmp/all_endpoints${random_str}.txt | sort -u  | tee tmp/all_endpoints_unique${random_str}.txt >/dev/null

## credentials checking

printf "Checking our js files for sweet credentials.."
cat tmp/all_js_files${random_str}.txt tmp/creds_search${random_str}.txt | parallel --gnu -j 15 "nuclei -t templates/credentials-disclosure-all.yaml -no-color -silent -target {}"


## parameters bruteforcing with modified Arjun

#printf "Arjun parameters discovery.."
#cat tmp/all_endpoints_unique${random_str}.txt | parallel -j 15 "python3 Arjun/arjun.py -f Arjun/db/params.txt -t 12 --get -u {} | httpx -sc -mc 200 -silent"


rm tmp/subjs${random_str}.txt tmp/gau${random_str}.txt tmp/spider${random_str}.txt tmp/all_js_files${random_str}.txt tmp/all_endpoints${random_str}.txt tmp/all_endpoints_unique${random_str}.txt
