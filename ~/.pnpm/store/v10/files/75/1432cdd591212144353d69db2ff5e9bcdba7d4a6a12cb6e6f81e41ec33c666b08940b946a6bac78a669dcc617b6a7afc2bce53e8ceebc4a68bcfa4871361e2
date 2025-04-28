import { computed as u } from "vue";
function e(o) {
  return {
    parameterMap: u(() => {
      var f;
      const s = {
        path: [],
        query: [],
        header: [],
        cookie: [],
        body: [],
        formData: []
      };
      o.pathParameters && o.pathParameters.forEach((i) => {
        i.in === "path" ? s.path.push(i) : i.in === "query" ? s.query.push(i) : i.in === "header" ? s.header.push(i) : i.in === "cookie" ? s.cookie.push(i) : i.in === "body" ? s.body.push(i) : i.in === "formData" && s.formData.push(i);
      });
      const h = ((f = o.information) == null ? void 0 : f.parameters) ?? [];
      return h && h.forEach((i) => {
        i.in === "path" ? s.path.push(i) : i.in === "query" ? s.query.push(i) : i.in === "header" ? s.header.push(i) : i.in === "cookie" ? s.cookie.push(i) : i.in === "body" ? s.body.push(i) : i.in === "formData" && s.formData.push(i);
      }), s;
    })
  };
}
export {
  e as useOperation
};
