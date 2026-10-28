*** Settings ***
Documentation
...    실행 전 DB 설정 정보 확인 → 없으면 INSERT (config/db_seed/<env>.sql)
...
...    시드 파일은 환경별이다. run_tests.sh 가 환경 인자로 골라 ${DB_SEED_FILE} 로
...    넘긴다(없음/IP → dev.sql, stg → stg.sql). 파일이 없으면 접속 없이 건너뛴다.
...    직접 돌릴 때: python -m robot --variable DB_SEED_FILE:config/db_seed/stg.sql
...    --variablefile config/env/stg.py setup/db_seed.robot
...
...    run_tests.sh 가 **본 실행 전에 한 번** 별도 robot 실행으로 부른다. tests/ 밖에
...    두어 `all` 이나 태그 실행에 섞이지 않는다. 별도 실행이라도 run_tests.sh 가
...    본 실행과 같은 --variablefile / --variable 을 넘기므로 접속 문자열 우선순위
...    (환경변수 PG_PDB_CONNSTR > --variable > config/env/<env>.py > variables.robot)는
...    본 실행과 같다.
...
...    블록마다 확인 SELECT(1행 1열 정수)가 0 이면 INSERT 하고, 다시 세어 1 이상인지
...    본다. 0 이 아니면 건너뛴다(멱등). 블록이 하나도 없으면 DB 에 접속하지 않는다.
...    ${PDB_CONNSTR_2} 가 있으면 두 번째 DB 에도 같은 일을 한다.
...
...    ★ `python -m robot tests/...` 로 직접 돌리면 이 단계는 돌지 않는다.
...      필요하면 먼저 `python -m robot setup/db_seed.robot` 를 부를 것.
...
...    생략: bash run_tests.sh <대상> --no-db-seed
...    확인만: bash run_tests.sh <대상> --db-seed-check

Resource    ../resources/variables.robot
Library     ../resources/CdsDbHelper.py    WITH NAME    SeedDb
Library     ../resources/DbSeedHelper.py    WITH NAME    Seed
Library     OperatingSystem

Suite Teardown    Close Seed DB Connections

*** Variables ***
${SEED_DB_CONN}      ${None}
${SEED_DB_CONN_2}    ${None}

*** Test Cases ***
DB 설정 정보 확인 및 적재
    [Documentation]    ${DB_SEED_FILE} 의 블록마다 확인 SELECT → 0건이면 INSERT → 재확인.
    ${exists}=    Run Keyword And Return Status    File Should Exist    ${DB_SEED_FILE}
    IF    not ${exists}
        Log    [Seed] 이 환경의 시드 파일이 없습니다 — DB 접속 없이 지나갑니다 (${DB_SEED_FILE})    console=True
        Pass Execution    시드 파일 없음
    END
    ${blocks}=    Seed.Load Seed Blocks    ${DB_SEED_FILE}
    ${count}=     Get Length    ${blocks}
    IF    ${count} == 0
        Log    [Seed] 시드 블록 없음 — DB 접속 없이 지나갑니다 (${DB_SEED_FILE})    console=True
        Pass Execution    시드 블록 없음
    END
    Log    [Seed] 시드 블록 ${count}건 (${DB_SEED_FILE}, 확인만=${DB_SEED_CHECK_ONLY})    console=True
    Open Seed DB Connections
    Apply Seed Blocks    ${SEED_DB_CONN}    DB1    ${blocks}
    IF    $SEED_DB_CONN_2 is not None
        Apply Seed Blocks    ${SEED_DB_CONN_2}    DB2    ${blocks}
    END

*** Keywords ***
Open Seed DB Connections
    [Documentation]
    ...    PDB 에 접속한다. 접속 문자열은 인자로 넘기지 않는다 — 비밀번호가 log.html 에
    ...    남기 때문이다(`Ensure CDS DB Connection` 과 같은 이유). 로그에는 마스킹된
    ...    문자열만 남는다. ${PDB_CONNSTR_2} 가 있으면 두 번째 DB 에도 붙는다.
    ${shown}=    SeedDb.Masked Conn Str
    Log    [Seed] PDB 접속 시도 — ${shown}    console=True
    ${conn}=    SeedDb.Db Connect    timeout=${DB_SEED_TIMEOUT}    autocommit=${FALSE}
    Set Suite Variable    ${SEED_DB_CONN}    ${conn}
    ${has_2nd}=    SeedDb.Has Second Db
    IF    ${has_2nd}
        ${shown_2}=    SeedDb.Masked Conn Str    which=${2}
        Log    [Seed] 두 번째 PDB 접속 시도 — ${shown_2}    console=True
        ${conn_2}=    SeedDb.Db Connect    timeout=${DB_SEED_TIMEOUT}    autocommit=${FALSE}    which=${2}
        Set Suite Variable    ${SEED_DB_CONN_2}    ${conn_2}
    END

Apply Seed Blocks
    [Documentation]
    ...    한 DB 에 블록 전체를 적용한다. 확인만 모드에서 빠진 블록이 있으면 WARN 으로
    ...    남기고 실패하지 않는다(본 실행은 진행된다).
    [Arguments]    ${conn}    ${db}    ${blocks}
    FOR    ${b}    IN    @{blocks}
        ${existing}=    SeedDb.Db Count    ${conn}    ${b}[check]
        IF    ${existing} > 0
            Log    [Seed] 있음 (${db}) — ${b}[name] (${existing}건)    console=True
            CONTINUE
        END
        IF    ${DB_SEED_CHECK_ONLY}
            Log    [Seed] 없음 (${db}) — ${b}[name] — 확인만 모드라 넣지 않았습니다    level=WARN
            CONTINUE
        END
        FOR    ${sql}    IN    @{b}[inserts]
            SeedDb.Db Execute    ${conn}    ${sql}
        END
        ${after}=    SeedDb.Db Count    ${conn}    ${b}[check]
        Should Be True    ${after} >= 1
        ...    msg=[Seed] ${db} — ${b}[name] INSERT 후 확인 SELECT 기대=1건 이상, 실제=${after} (확인 SELECT 와 INSERT 가 같은 행을 가리키는지 볼 것)
        Log    [Seed] 적재 (${db}) — ${b}[name]    console=True
    END

Close Seed DB Connections
    SeedDb.Db Close    ${SEED_DB_CONN}
    SeedDb.Db Close    ${SEED_DB_CONN_2}
