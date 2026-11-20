*** Settings ***
Documentation    NAG/PCF 통합 슈트의 경로별 연결 수명주기 관리.
Resource    ${CURDIR}/pcf_keywords.robot
Resource    ${CURDIR}/lrs_keywords.robot
Resource    ${CURDIR}/ssh_keywords.robot

*** Keywords ***
Initialize NAG Regression
    [Documentation]    PG BarodNoti.cfg 에서 NAG/PCF 포트를 읽고, 선택된 테스트의 첫 경로에서만 연결하도록 상태를 초기화한다.
    Load NAG Ports From BNOTI Cfg
    Set Suite Variable    ${NAG_PHASE_STARTED}    ${FALSE}
    Set Suite Variable    ${PCF_PHASE_STARTED}    ${FALSE}

Prepare NAG Regression Test
    [Documentation]    NAG 경로 후 PCF 경로로 한 번 전환하며 일반 TC 간 소켓은 공유한다.
    TRY
        ${is_pcf}=    Run Keyword And Return Status    List Should Contain Value    ${TEST TAGS}    pcf
        IF    $is_pcf
            IF    not $PCF_PHASE_STARTED
                IF    $NAG_PHASE_STARTED
                    Close NAG Regression Connections
                END
                Start PCF Integration Path
                Set Suite Variable    ${PCF_PHASE_STARTED}    ${TRUE}
            END
            Check PCF And NAG Socket
        ELSE
            IF    $PCF_PHASE_STARTED
                Fatal Error    PCF 경로 이후 NAG 경로로 되돌아갈 수 없습니다. TC 번호 순서를 유지하십시오.
            END
            IF    not $NAG_PHASE_STARTED
                Start NAG Request Path
                Set Suite Variable    ${NAG_PHASE_STARTED}    ${TRUE}
            END
            Check NAG Socket
            Check LRS Socket
        END
    EXCEPT    AS    ${error}
        Fatal Error    NAG 통합 슈트 선행조건 실패: ${error}
    END

Start NAG Request Path
    [Documentation]    기존 NAG Suite Setup을 보존한다. LRS 준비 후 NAG를 연결한다.
    Ensure PG Process Running    G_BNOTI201    G_LRS201    CDS201
    # Existing startup-settle wait moved from nag_tests.robot; no additional wait policy introduced.
    Sleep    ${PG_SSH_SETTLE}
    Log    [NAG 선행조건] LRS→PCF 수신 대기: ${LRS_SERVER_HOST}:${LRS_SERVER_PORT}    console=True
    Suite LRS Accept
    Handle LRS Hello
    Check LRS Socket
    Log    [NAG 선행조건] LRS→PCF 연결 및 Hello 완료. NAG 연결을 시작합니다.    console=True
    Suite Connect NAG

Start PCF Integration Path
    [Documentation]    기존 PCF Suite Setup을 보존한다. NAG Hello 성공 후 PCF를 연결한다.
    Ensure PG Process Running    CDS201
    # Existing startup-settle wait moved from pcf_tests.robot; retained as documented legacy behavior.
    Sleep    ${PG_SSH_SETTLE}
    Suite Connect With NAG    ${PCF_PG_HOST}    ${PCF_PG_PORT}    ${PCF_TIMEOUT}

Close NAG Regression Connections
    [Documentation]    경로 전환 또는 Suite Teardown에서 LRS/PCF/NAG를 모두 정리한다.
    TRY
        Suite LRS Disconnect
    FINALLY
        Suite Disconnect With NAG
    END
    Set Suite Variable    ${LRS_CONN}    ${NONE}
    Set Suite Variable    ${LRS_SRV_SOCK}    ${NONE}
    Set Suite Variable    ${PCF_SOCK}    ${NONE}
    Set Suite Variable    ${NAG_SOCK}    ${NONE}
