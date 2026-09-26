# cdp_check_exception reports JavaScript errors with and without context

    Code
      cdp_check_exception(res, "validating CSS")
    Condition
      Error:
      ! JavaScript error validating CSS: boom.

---

    Code
      cdp_check_exception(res)
    Condition
      Error:
      ! JavaScript error: boom.

