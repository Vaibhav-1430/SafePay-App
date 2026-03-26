function categoryFromText(text) {
  const n = String(text || '').toLowerCase();
  if (/(food|dinner|restaurant|swiggy|zomato)/.test(n)) return 'food';
  if (/(cab|uber|ola|fuel|petrol|metro|travel)/.test(n)) return 'transport';
  if (/(rent|electricity|water|internet|bill)/.test(n)) return 'bills';
  if (/(movie|shopping|amazon|flipkart|entertainment)/.test(n)) return 'shopping';
  if (/(medicine|hospital|pharmacy|doctor)/.test(n)) return 'health';
  return 'other';
}

function summarizeAssistant(question, transactions) {
  const txs = Array.isArray(transactions) ? transactions : [];
  const breakdown = {};
  let total = 0;

  for (const tx of txs) {
    const amount = Number(tx.amount || 0);
    if (!Number.isFinite(amount) || amount <= 0) continue;
    total += amount;

    const category = String(tx.category || '').trim().toLowerCase()
      || categoryFromText(`${tx.note || ''} ${tx.receiver_name || ''}`);

    breakdown[category] = (breakdown[category] || 0) + amount;
  }

  let topCategory = null;
  let topValue = 0;
  for (const [category, value] of Object.entries(breakdown)) {
    if (value > topValue) {
      topValue = value;
      topCategory = category;
    }
  }

  const q = String(question || '').toLowerCase();
  let answer = `You spent Rs ${Math.round(total)} in this period.`;

  if (q.includes('most') || q.includes('where')) {
    answer = topCategory
      ? `Most spending went to ${topCategory} (Rs ${Math.round(topValue)}).`
      : 'I could not find enough transactions to infer top category yet.';
  } else if (q.includes('summarize') || q.includes('summary')) {
    answer = topCategory
      ? `Total spending is Rs ${Math.round(total)}. Top category is ${topCategory}.`
      : `Total spending is Rs ${Math.round(total)}. Not enough data for a top category.`;
  }

  return {
    answer,
    monthly_total: Number(total.toFixed(2)),
    top_category: topCategory,
    category_breakdown: breakdown,
  };
}

module.exports = {
  summarizeAssistant,
};
