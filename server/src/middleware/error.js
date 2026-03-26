function notFoundHandler(req, res) {
  res.status(404).json({ error: 'Route not found' });
}

function errorHandler(err, req, res, next) {
  console.error('[ServerError]', err);
  res.status(500).json({ error: 'Internal server error' });
}

module.exports = {
  notFoundHandler,
  errorHandler,
};
