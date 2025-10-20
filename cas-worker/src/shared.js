function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function validateQuery(request) {
  const query = request.query || {};
  const { account_handle: accountHandle, project_handle: projectHandle } =
    query;

  if (!accountHandle || !projectHandle) {
    return {
      error: "Missing account_handle or project_handle query parameter",
      status: 400,
    };
  }

  return { accountHandle, projectHandle };
}

function decodeCasId(rawCasId) {
  if (typeof rawCasId !== "string") return null;

  try {
    return decodeURIComponent(rawCasId);
  } catch {
    return null;
  }
}

export { jsonResponse, validateQuery, decodeCasId };
