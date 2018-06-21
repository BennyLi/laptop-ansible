#! /usr/bin/env bash

ansible-playbook -i machines/iteratec --ask-become-pass --ask-vault-pass $@ arch.yml
