"""Contract §9: each canonical question gets an answer and the SQL behind it (§5.3).

Live checks stay basic until the real response shape is captured (artifact
07_agent_response.json, C6c). The mock-mode metric lineage per question is covered in
tests/unit/test_data_layer.py.
"""

import pytest

from utils import config


@pytest.mark.parametrize("question", config.CANONICAL_QUESTIONS,
                         ids=[f"q{i}" for i in range(1, len(config.CANONICAL_QUESTIONS) + 1)])
def test_canonical_question_is_answered_with_sql(forge, question):
    result = forge.ask_agent(question)
    assert result["status"] != "unparseable"
    assert result["answer"].strip(), "empty answer"
    assert result["sql"], "no SQL: the agent didn't query the semantic view"
    assert result["tools_used"], "no tool was used"


def test_there_are_eight_canonical_questions():
    assert len(config.CANONICAL_QUESTIONS) == 8
    assert config.CANONICAL_QUESTIONS[7] == "Which plants have the worst on-time delivery?"  # CR-003
