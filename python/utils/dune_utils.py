from dune_client.client import DuneClient
from dune_client.query import QueryBase
from dune_client.types import QueryParameter, DuneRecord, ParameterType


def query_dune(
    query_id: int, api_key: str, latest_block: int | None = None
) -> list[DuneRecord]:
    """
    Run a Dune query and return the results.

    :param query_id: The ID of the Dune query.
    :param api_key: The API key Dune.
    :param latest_block: The latest block to query (optional).
    :return: The results of the Dune query.
    """
    dune = DuneClient(api_key=api_key)
    if latest_block is not None:
        params = [
            QueryParameter(
                name="max_block",
                value=latest_block,
                parameter_type=ParameterType.NUMBER,
            )
        ]
    else:
        params = []
    query = QueryBase(
        query_id=query_id,
        params=params,
    )
    return dune.run_query(query).get_rows()
