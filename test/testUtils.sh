#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# Default log level
# shellcheck disable=SC2034
LOG_LEVEL="DEBUG"

# shellcheck source=/dev/null
source "lib/functions/log.sh"

# TODO: use TEST_CASE_FOLDER instead of redefining this after we extract the
# initialization of TEST_CASE_FOLDER from linter.sh
# shellcheck disable=SC2034
LINTERS_TEST_CASE_DIRECTORY="test/linters"

# shellcheck disable=SC2034
LANGUAGES_WITH_FIX_MODE=(
  "ANSIBLE"
  "CLANG_FORMAT"
  "CSHARP"
  "CSS"
  "ENV"
  "GO_MODULES"
  "GO"
  "GOOGLE_JAVA_FORMAT"
  "GROOVY"
  "JAVASCRIPT_ES"
  "JAVASCRIPT_PRETTIER"
  "JAVASCRIPT_STANDARD"
  "JSON"
  "JSONC"
  "JSX"
  "MARKDOWN"
  "NATURAL_LANGUAGE"
  "POWERSHELL"
  "PROTOBUF"
  "PYTHON_BLACK"
  "PYTHON_ISORT"
  "PYTHON_RUFF"
  "RUBY"
  "RUST_2015"
  "RUST_2018"
  "RUST_2021"
  "RUST_CLIPPY"
  "SCALAFMT"
  "SHELL_SHFMT"
  "SNAKEMAKE_SNAKEFMT"
  "SQLFLUFF"
  "TERRAFORM_FMT"
  "TSX"
  "TYPESCRIPT_ES"
  "TYPESCRIPT_PRETTIER"
  "TYPESCRIPT_STANDARD"
)

# TODO: extract this list from linter.sh (see REMOVE_ARRAY) instead of
# redefining it here
# shellcheck disable=SC2034
LANGUAGES_NOT_IN_SLIM_IMAGE=(
  "ARM"
  "CSHARP"
  "POWERSHELL"
  "RUST_2015"
  "RUST_2018"
  "RUST_2021"
  "RUST_CLIPPY"
)

function AssertArraysElementsContentMatch() {
  local ARRAY_1_VARIABLE_NAME="${1}"
  local ARRAY_2_VARIABLE_NAME="${2}"
  local -n ARRAY_1="${ARRAY_1_VARIABLE_NAME}"
  local -n ARRAY_2="${ARRAY_2_VARIABLE_NAME}"
  if [[ "${ARRAY_1[*]}" == "${ARRAY_2[*]}" ]]; then
    debug "${ARRAY_1_VARIABLE_NAME} (${ARRAY_1[*]}) matches the expected value: ${ARRAY_2[*]}"
    RETURN_CODE=0
  else
    error "${ARRAY_1_VARIABLE_NAME} (${ARRAY_1[*]}) doesn't match the expected value: ${ARRAY_2[*]}"
    RETURN_CODE=1
  fi
  unset -n ARRAY_1
  unset -n ARRAY_2
  return ${RETURN_CODE}
}

function CheckUnexpectedGitChanges() {
  local GIT_REPOSITORY_PATH="${1}"
  # Check if there are unexpected changes in the working directory:
  # - Unstaged changes
  # - Changes that are staged but not committed
  # - Untracked files and directories
  if ! git -C "${GIT_REPOSITORY_PATH}" diff --exit-code --quiet ||
    ! git -C "${GIT_REPOSITORY_PATH}" diff --cached --exit-code --quiet ||
    ! git -C "${GIT_REPOSITORY_PATH}" ls-files --others --exclude-standard --directory; then
    echo "There are unexpected changes in the working directory of the ${GIT_REPOSITORY_PATH} Git repository."
    git -C "${GIT_REPOSITORY_PATH}" status
    return 1
  fi
}

AssertFileContentsMatch() {
  local FILE_1_PATH="${1}"
  local FILE_2_PATH="${2}"
  if diff -r "${FILE_1_PATH}" "${FILE_2_PATH}"; then
    echo "${FILE_1_PATH} contents match with ${FILE_2_PATH} contents"
    return 0
  else
    echo "${FILE_1_PATH} contents don't match with ${FILE_2_PATH} contents"
    return 1
  fi
}

IsLanguageInSlimImage() {
  local LANGUAGE="${1}"
  if [[ " ${LANGUAGES_NOT_IN_SLIM_IMAGE[*]} " =~ [[:space:]]${LANGUAGE}[[:space:]] ]]; then
    debug "${LANGUAGE} is not available in the Super-linter slim image"
    return 1
  else
    debug "${LANGUAGE} is available in the Super-linter slim image"
    return 0
  fi
}

RemoveTestLeftovers() {
  local LEFTOVERS_TO_CLEAN=()
  LEFTOVERS_TO_CLEAN+=("${SUPER_LINTER_WORKSPACE}/${LINTERS_TEST_CASE_DIRECTORY}/rust_clippy/bad/target")
  LEFTOVERS_TO_CLEAN+=("${SUPER_LINTER_WORKSPACE}/${LINTERS_TEST_CASE_DIRECTORY}/rust_clippy/bad/Cargo.lock")
  LEFTOVERS_TO_CLEAN+=("${SUPER_LINTER_WORKSPACE}/${LINTERS_TEST_CASE_DIRECTORY}/rust_clippy/good/target")
  LEFTOVERS_TO_CLEAN+=("${SUPER_LINTER_WORKSPACE}/${LINTERS_TEST_CASE_DIRECTORY}/rust_clippy/good/Cargo.lock")
  # Delete leftovers in pwd in case the workspace is not pwd
  LEFTOVERS_TO_CLEAN+=("$(pwd)/${LINTERS_TEST_CASE_DIRECTORY}/rust_clippy/bad/target")
  LEFTOVERS_TO_CLEAN+=("$(pwd)/${LINTERS_TEST_CASE_DIRECTORY}/rust_clippy/bad/Cargo.lock")
  LEFTOVERS_TO_CLEAN+=("$(pwd)/${LINTERS_TEST_CASE_DIRECTORY}/rust_clippy/good/target")
  LEFTOVERS_TO_CLEAN+=("$(pwd)/${LINTERS_TEST_CASE_DIRECTORY}/rust_clippy/good/Cargo.lock")

  # These variables are defined after configuring test cases, so they might not
  # have been initialized yet
  if [[ -v LOG_FILE_PATH ]] &&
    [[ -n "${LOG_FILE_PATH}" ]]; then
    LEFTOVERS_TO_CLEAN+=("${LOG_FILE_PATH}")
    LEFTOVERS_TO_CLEAN+=("$(pwd)/$(basename "${LOG_FILE_PATH}")")
  fi

  if [[ -v SUPER_LINTER_GITHUB_STEP_SUMMARY_FILE_PATH ]] &&
    [[ -n "${SUPER_LINTER_GITHUB_STEP_SUMMARY_FILE_PATH}" ]]; then
    LEFTOVERS_TO_CLEAN+=("${SUPER_LINTER_GITHUB_STEP_SUMMARY_FILE_PATH}")
    LEFTOVERS_TO_CLEAN+=("$(pwd)/$(basename "${SUPER_LINTER_GITHUB_STEP_SUMMARY_FILE_PATH}")")
  fi

  if [[ -v SUPER_LINTER_MAIN_OUTPUT_PATH ]] &&
    [[ -n "${SUPER_LINTER_MAIN_OUTPUT_PATH}" ]]; then
    LEFTOVERS_TO_CLEAN+=("${SUPER_LINTER_MAIN_OUTPUT_PATH}")
    LEFTOVERS_TO_CLEAN+=("$(pwd)/$(basename "${SUPER_LINTER_MAIN_OUTPUT_PATH}")")
  fi

  if [[ -v SUPER_LINTER_SUMMARY_FILE_PATH ]] &&
    [[ -n "${SUPER_LINTER_SUMMARY_FILE_PATH}" ]]; then
    LEFTOVERS_TO_CLEAN+=("${SUPER_LINTER_SUMMARY_FILE_PATH}")
    LEFTOVERS_TO_CLEAN+=("$(pwd)/$(basename "${SUPER_LINTER_SUMMARY_FILE_PATH}")")
  fi

  debug "Cleaning eventual test leftovers: ${LEFTOVERS_TO_CLEAN[*]}"
  sudo rm -rfv "${LEFTOVERS_TO_CLEAN[@]}"
}