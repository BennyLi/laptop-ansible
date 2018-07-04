#! /usr/bin/env bash

ansible_cmd="ansible-playbook -i machines/iteratec --ask-become-pass"
playbook="laptop-setup-playbook.yml"

#####
# Enriches the tags list by using my own subtag system.
#
# Examples:
#   TAGS: [desktop:i3, desktop:compton, dotfiles]
#   ansible-playbook -t desktop playbook.yml
#   result: ansible-playbook -t desktop:i3,desktop:compton playbook.yml
#
#   TAGS: [desktop:i3, desktop:i3:bar:blocks, desktop:compton, dotfiles]
#   ansible-playbook -t desktop:i3 playbook.yml
#   result: ansible-playbook -t desktop:i3,desktop:i3:bar:blocks playbook.yml
#####
function enrich_tags {
  # Split the comma seperated string into an array
  local tags=(${@//,/ })
  local all_tags=$($ansible_cmd --list-tags $playbook | sed -nr 's/.*TAGS: \[(.*)\]/\1/p')
  all_tags=(${all_tags//,/ })
  local result_tags=""

  for tag in ${tags[@]}; do
    for all_tag in ${all_tags[@]}; do
      if [[ $all_tag = "$tag"* ]]; then
        result_tags="$result_tags,$all_tag"
      fi
    done
  done
  # remove the first , from the string
  echo ${result_tags:1}
}

while (( "$#" )); do
  case "$1" in
    -t | --tags)
      enriched_tags=$(enrich_tags "$2")
      if [ -z "$enriched_tags" ]; then
        >&2 echo "No tags for '$1' found in this playbook"
        exit 1
      else
        PARAMS="$PARAMS $1 $enriched_tags"
      fi
      shift 2
      ;;
    *)
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done

#  --ask-vault-pass
$ansible_cmd $PARAMS $playbook
