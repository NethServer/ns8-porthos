*** Settings ***
Library           SSHLibrary
Library           DateTime

*** Variables ***
${SSH_KEYFILE}    %{HOME}/.ssh/id_ecdsa
${JOURNAL_SINCE}    0

*** Keywords ***
Connect to the node
    Open Connection   ${NODE_ADDR}
    Login With Public Key    root    ${SSH_KEYFILE}

Wait until boot completes
    ${output} =    Execute Command    systemctl is-system-running  --wait
    Should Be True    '${output}' == 'running' or '${output}' == 'degraded'

Save the journal begin timestamp
    ${tsnow} =    Get Current Date    result_format=epoch
    Set Global Variable    ${JOURNAL_SINCE}    ${tsnow}

Collect the suite journal
    Execute Command    printf "Test suite starts at %s\n" "$(date -d @${JOURNAL_SINCE})" >journal-dump.log
    Execute Command    journalctl -o short-precise -S @${JOURNAL_SINCE} >journal-dump.log
    Get File    journal-dump.log    ${OUTPUT DIR}/journal-${SUITE NAME}.log

Start rsync service mock
    ${out}    ${err}    ${rc} =    Execute Command
    ...    podman run -d --name rsync-mock --replace --network=host --privileged --workdir=/srv --env=RSYNCD_NETWORK=127.0.0.0/8 --env=RSYNCD_ADDRESS=127.0.0.1 --env=RSYNCD_PORT=10000 --env=RSYNCD_USER= --env=RSYNCD_PASSWORD= --env=RSYNCD_SYSLOG_TAG=rsync-mock --volume=/dev/log:/dev/log $(sed -n '/^RSYNC_IMAGE=/ s/RSYNC_IMAGE=// p' /etc/nethserver/core.env) && { while ! exec 3<>/dev/tcp/127.0.0.1/10000; do sleep 1 ; done ; }
    ...    timeout=15s    return_rc=${TRUE}    return_stderr=${TRUE}    return_stdout=${TRUE}
    Should Be Equal As Integers    ${rc}  0
    ${out}  ${err}  ${rc} =  Execute Command    podman exec rsync-mock sh -c 'mkdir -vp rocky/9/BaseOS/x86_64/os/repodata rocky/9/AppStream/x86_64/os/repodata && echo init | tee rocky/9/BaseOS/x86_64/os/repodata/repomd.xml | tee rocky/9/AppStream/x86_64/os/repodata/repomd.xml'
    ...  timeout=15s    return_rc=True    return_stderr=True
    Should Be Equal As Integers    ${rc}  0

Stop rsync service mock
    Execute Command    podman stop -t 3 rsync-mock

*** Settings ***
Suite Setup       Run Keywords
                  ...    Connect to the Node
                  ...    Wait until boot completes
                  ...    Save the journal begin timestamp
                  ...    Start rsync service mock

Suite Teardown    Run Keywords
                  ...    Stop rsync service mock
                  ...    Collect the suite journal
