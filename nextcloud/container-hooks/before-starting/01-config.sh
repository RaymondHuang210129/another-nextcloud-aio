#!/usr/bin/env bash

set -e

if /var/www/html/occ status | grep -q "installed: false"; then
    echo "Nextcloud is not installed. Skipping configuration."
    exit 0
fi

/var/www/html/occ config:system:set memcache.local --value="\OC\Memcache\APCu"
/var/www/html/occ config:system:set memcache.locking --value="\OC\Memcache\Redis"
/var/www/html/occ config:system:set filelocking.enabled --value="true" --type=boolean
/var/www/html/occ config:system:set redis host --value="redis"
/var/www/html/occ config:system:set redis port --value="6379"
/var/www/html/occ config:system:set redis timeout --value="1.5"

/var/www/html/occ config:system:set trusted_domains --value="[\"${TRUSTED_PROXIES}\", \"${FQDN}\"]" --type=json
/var/www/html/occ config:system:set trusted_proxies --value="[\"${TRUSTED_PROXIES}\"]" --type=json
/var/www/html/occ config:system:set overwritehost --value="${FQDN}"
/var/www/html/occ config:system:set overwriteprotocol --value="https"
/var/www/html/occ config:system:set overwrite.cli.url --value="https://${FQDN}/"

/var/www/html/occ config:system:set preview_imaginary_url --value="http://nextcloud-imaginary:9000/"
/var/www/html/occ config:system:set allow_local_remote_servers --value="true" --type=boolean

/var/www/html/occ config:system:set enabledPreviewProviders 0 --value="OC\Preview\MP3"
/var/www/html/occ config:system:set enabledPreviewProviders 1 --value="OC\Preview\TXT"
/var/www/html/occ config:system:set enabledPreviewProviders 2 --value="OC\Preview\MarkDown"
/var/www/html/occ config:system:set enabledPreviewProviders 3 --value="OC\Preview\OpenDocument"
/var/www/html/occ config:system:set enabledPreviewProviders 4 --value="OC\Preview\Krita"
/var/www/html/occ config:system:set enabledPreviewProviders 5 --value="OC\Preview\Imaginary"
