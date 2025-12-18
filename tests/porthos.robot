*** Settings ***
Library    SSHLibrary

*** Variables ***
${SCENARIO}     install
${FQDN}         porthos.example.org

*** Test Cases ***
Module installation
    [Tags]    create
    IF    r'${SCENARIO}' == 'update'
        Set Local Variable  ${iurl}  ghcr.io/nethserver/porthos:1.3.0-dev.1
    ELSE
        Set Local Variable  ${iurl}  ${IMAGE_URL}
    END
    ${output}  ${rc} =    Execute Command    add-module ${iurl} 1
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    &{output} =    Evaluate    ${output}
    Set Global Variable    ${MID}    ${output.module_id}

Configure module
    ${out}  ${err}  ${rc} =  Execute Command    runagent -m ${MID} podman volume rm -f webroot
    ...    return_rc=True    return_stderr=True
    Should Be Equal As Integers    ${rc}  0    "volume removal error: ${err}"
    Run task    module/${MID}/configure-module  {"source": "rsync://127.0.0.1:10000/data","retention":45}

Check module update
    [Tags]    create
    Log  Scenario ${SCENARIO} with ${IMAGE_URL}  console=${True}
    IF    r'${SCENARIO}' == 'update'
        ${out}  ${rc} =  Execute Command  api-cli run update-module --data '{"force":true,"module_url":"${IMAGE_URL}","instances":["${MID}"]}'  return_rc=${True}
        Should Be Equal As Integers  ${rc}  0  action update-module ${IMAGE_URL} failed
    END

Check module config
    &{output} =    Run task    module/${MID}/get-configuration  {}
    Should Be Equal    ${output}[source]    rsync://127.0.0.1:10000/data
    Set Global Variable    ${FQDN}    ${output}[server_name]

Check take-snapshot run
    ${out}  ${err}  ${rc} =  Execute Command    runagent -m ${MID} take-snapshot
    ...    return_rc=True    return_stderr=True
    Should Be Equal As Integers    ${rc}  0    "take-snapshot error: ${err}"
    Rename snapshot to make it 7 days older

Check sync-head run
    ${out}  ${err}  ${rc} =  Execute Command    runagent -m ${MID} sync-head
    ...    return_rc=True    return_stderr=True
    Should Be Equal As Integers    ${rc}  0    "sync-head error: ${err}"

Web root matches
    ${out}  ${err}  ${rc} =  Execute Command    curl -f http://${FQDN}/
    ...    return_rc=True    return_stderr=True
    Should Be Equal As Integers    ${rc}  0    "curl error: ${err}"
    Should Contain    ${out}    Porthos    "Porthos not found in ${out}"

Mirrorlist returns urls
    URL Content Should Be Equal  http://${FQDN}/mirrorlist?repo=BaseOS-9&arch=x86_64  https://${FQDN}/rocky/9/BaseOS/x86_64/os/
    URL Content Should Be Equal  http://${FQDN}/mirrorlist?repo=AppStream-9&arch=x86_64  https://${FQDN}/rocky/9/AppStream/x86_64/os/

DNF metadata is present
    URL Content Should Be Equal  https://${FQDN}/rocky/9/AppStream/x86_64/os/repodata/repomd.xml  init

Content is served from latest snapshot
    Simulate DNF upstream update    update-1
    URL Content Should Be Equal  https://${FQDN}/rocky/9/AppStream/x86_64/os/repodata/repomd.xml  update-1

Authenticated client sees original snapshot
    URL Content Should Be Equal  https://${FQDN}/rocky/9/AppStream/x86_64/os/repodata/repomd.xml  init  user:pass

Check module removal
    [Tags]    remove
    ${rc} =    Execute Command    remove-module --no-preserve ${MID}
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0


*** Keywords ***
URL Content Should Be Equal
    [Arguments]    ${url}    ${content}    ${credentials}=
    IF  r'${credentials}' == ""
        ${out}  ${err}  ${rc} =  Execute Command    curl -k -f '${url}'
        ...    return_rc=True    return_stderr=True
    ELSE
        ${out}  ${err}  ${rc} =  Execute Command    curl -k -f -u '${credentials}' '${url}'
        ...    return_rc=True    return_stderr=True
    END
    Should Be Equal As Integers    ${rc}  0    "curl error: ${err}"
    Should Be Equal    ${out}    ${content}
    ...    strip_spaces=True

Simulate DNF upstream update
    [Arguments]    ${content}
    ${out}  ${err}  ${rc} =  Execute Command    podman exec rsync-mock sh -c 'echo ${content} | tee rocky/9/BaseOS/x86_64/os/repodata/repomd.xml | tee rocky/9/AppStream/x86_64/os/repodata/repomd.xml'
    ...  timeout=1s    return_rc=True    return_stderr=True
    Should Be Equal As Integers    ${rc}  0
    ${out}  ${err}  ${rc} =  Execute Command    runagent -m ${MID} take-snapshot
    ...    return_rc=True    return_stderr=True
    Should Be Equal As Integers    ${rc}  0    "take-snapshot error: ${err}"

Rename snapshot to make it ${num} days older
    ${out}  ${err}  ${rc} =  Execute Command    runagent -m ${MID} podman exec nginx sh -c 'cd /srv/porthos/webroot ; mv -v $(ls -1d d20* | tail -1) $(date -d @$(( $(date -D "d%Y%m%dt%H%M%S" -d $(ls -1d d20* | tail -1) +%s) - ${num}*86400 )) +"d%Y%m%dt%H%M%S00")'
    ...  timeout=1s    return_rc=True    return_stderr=True
    Should Be Equal As Integers    ${rc}  0


Run task
    [Arguments]    ${action}    ${input}    ${decode_json}=${TRUE}    ${rc_expected}=0
    ${stdout}    ${stderr}    ${rc} =     Execute Command    api-cli run ${action} --data '${input}'    return_stdout=True    return_stderr=True    return_rc=True
    Should Be Equal As Integers    ${rc_expected}    ${rc}    Run task ${action} failed!${\n}${stderr}
    IF    ${decode_json} and len($stdout) > 0
        ${response} =    Evaluate    json.loads('''${stdout}''')    modules=json
    ELSE
        ${response} =    Set Variable    ${stdout}
    END
    RETURN    ${response}
