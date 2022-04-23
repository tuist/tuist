const relativeTimeFormatter = new Intl.RelativeTimeFormat('en-GB', {
  numeric: 'auto',
});

const relativeDate = (date: Date) => {
  const currentDate = new Date();
  if (date.getUTCDate() === currentDate.getUTCDate()) {
    if (date.getUTCHours() === currentDate.getUTCHours()) {
      return relativeTimeFormatter.format(
        date.getUTCMinutes() - currentDate.getUTCMinutes(),
        'minutes',
      );
    }
    return relativeTimeFormatter.format(
      date.getUTCHours() - currentDate.getUTCHours(),
      'hours',
    );
  }
  return date.toLocaleString();
};

export default relativeDate;
