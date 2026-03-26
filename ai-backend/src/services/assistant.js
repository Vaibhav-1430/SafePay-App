function summarizeSpending(transactions = []) {
  const byCategory = {};
  let monthlyTotal = 0;

  for (const tx of transactions) {
    const amount = Number(tx.amount || 0);
    if (amount <= 0) continue;
    monthlyTotal += amount;

    const note = String(tx.note || '').toLowerCase();
    const merchant = String(tx.receiver_name || tx.receiverName || '').toLowerCase();
    const text = `${note} ${merchant}`;

    let category = 'other';
    if (/(food|zomato|swiggy|restaurant|cafe)/.test(text)) category = 'food';
    else if (/(uber|ola|fuel|petrol|metro|travel)/.test(text)) category = 'transport';
    else if (/(rent|electricity|internet|water|bill)/.test(text)) category = 'bills';
    else if (/(movie|amazon|flipkart|shopping)/.test(text)) category = 'shopping';
    else if (/(hospital|pharmacy|medicine|doctor)/.test(text)) category = 'health';

    byCategory[category] = (byCategory[category] || 0) + amount;
  }

  const entries = Object.entries(byCategory);
  const topCategory = entries.length
    ? entries.reduce((a, b) => (a[1] >= b[1] ? a : b))[0]
    : null;

  return { monthlyTotal, byCategory, topCategory };
}

function chatAssistant(question = '', transactions = []) {
  const { monthlyTotal, byCategory, topCategory } = summarizeSpending(transactions);
  const q = String(question || '').toLowerCase();

  let answer;
  if (/how much|spent|total/.test(q)) {
    answer = `You spent INR ${monthlyTotal.toFixed(0)} in this period.`;
  } else if (/where|most|category/.test(q)) {
    answer = topCategory
      ? `Most spending went to ${topCategory} (INR ${(byCategory[topCategory] || 0).toFixed(0)}).`
      : 'Not enough spending history to identify a top category.';
  } else {
    answer = topCategory
      ? `Total spending is INR ${monthlyTotal.toFixed(0)} and top category is ${topCategory}.`
      : `Total spending is INR ${monthlyTotal.toFixed(0)}.`;
  }

  return {
    answer,
    monthly_total: monthlyTotal,
    top_category: topCategory,
    category_breakdown: byCategory,
  };
}

module.exports = { chatAssistant };
